#include "video.h"

#ifndef NO_FFMPEG

#include "video_libav.h"

/**
 * The maximum wait time for a frame to be decoded (`WAIT_FRAMES_AVAILABLE`) is hard to
 * compromise on. It shouldn't wait forever in case the threading code does something
 * unexpected but also be generous enough for non-realtime rendering on low-power
 * systems (where decoding a big, complex video codec might take a really long time).
 * Something between 10 and 30 seconds seems about right, but this is a pure guess.
 *
 * TODO [feature]: Change the wait time depending on realtime or non-realtime mode.
 *                 AVS knows which rendering mode it's in, so AVS_Video can know too.
 */
#define WAIT_FRAMES_AVAILABLE      20000
#define WAIT_NEED_FRAMES_OR_STOP   500
#define WAIT_CACHING_THREAD_FINISH WAIT_NEED_FRAMES_OR_STOP * 2

uint32_t AVS_Video::frame_cache_thread_func(void* this_video) {
    auto thisv = (AVS_Video*)this_video;
    while (thisv->cache_frames()) {
        ;
    }
    return 0;
}

AVS_Video::AVS_Video(const char* filename,
                     int64_t max_cache_length,
                     int64_t backward_cache_length)
    : filename(filename),
      error(NULL),
      av(new LibAV()),
      cache(max_cache_length, backward_cache_length, 0),
      need_frames(signal_create_single()),
      frames_available(signal_create_single()),
      stop_caching(signal_create_single()),
      playback_lock(lock_init()) {
    if (!this->av->loaded) {
        this->error =
            !LibAV::load_error.empty() ? LibAV::load_error.c_str() : "libav not loaded";
        return;
    }
    if (!this->init()) {
        return;
    }
    this->caching_thread = thread_create(frame_cache_thread_func, this);
}

AVS_Video::~AVS_Video() {
    if (this->av->loaded) {
        signal_set(this->stop_caching);
        thread_join(this->caching_thread, WAIT_CACHING_THREAD_FINISH);
        signal_destroy(this->need_frames);
        signal_destroy(this->frames_available);
        signal_destroy(this->stop_caching);
        lock_destroy(this->playback_lock);
        this->close();
    }
    delete this->av;
}

bool AVS_Video::init() {
    if (this->av->demuxer != NULL) {
        this->close();
    }
    this->av->demuxer = LibAV::alloc_context();
    if (!this->av->demuxer) {
        this->error = "demuxer context alloc failed";
        return false;
    }
    if (LibAV::open_input(&this->av->demuxer, this->filename.c_str(), NULL, NULL)
        != 0) {
        this->error = "open input failed";
        return false;
    }

    for (size_t i = 0; i < this->av->demuxer->nb_streams; i++) {
        this->av->codec_params = this->av->demuxer->streams[i]->codecpar;
        if (this->av->codec_params->codec_type == AVMEDIA_TYPE_VIDEO) {
            this->video_streams.push_back(i);
            break;
        }
    }
    if (this->video_streams.empty()) {
        this->error = "no video stream found";
        return false;
    }
    this->video_stream =
        LibAV::find_best_stream(this->av->demuxer, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (this->video_stream < 0) {
        this->error = "select best video stream failed (this shouldn't occur)";
        return false;
    }
    return this->init_codec();
}

bool AVS_Video::init_codec() {
    if (this->av->decoder != NULL) {
        this->close_codec();
    }
    this->av->codec = LibAV::find_decoder(
        this->av->demuxer->streams[this->video_stream]->codecpar->codec_id);
    if (this->av->codec == NULL) {
        this->error = "no decoder for video codec";
        return false;
    }

    this->av->decoder = LibAV::alloc_context3(this->av->codec);
    if (!this->av->decoder) {
        this->error = "decoder context alloc failed";
        return false;
    }
    if (LibAV::parameters_to_context(this->av->decoder, this->av->codec_params) < 0) {
        this->error = "decoder context init failed";
        return false;
    }
    if (LibAV::open2(this->av->decoder, this->av->codec, NULL) < 0) {
        this->error = "decoder open failed";
        return false;
    }

    this->av->packet = LibAV::packet_alloc();
    if (!this->av->packet) {
        this->error = "cannot allocate decoder packet";
        return false;
    }
    this->av->frame = LibAV::frame_alloc();
    if (!this->av->frame) {
        this->error = "cannot allocate decoder frame";
        return false;
    }
    auto stream = this->av->demuxer->streams[this->video_stream];
    int64_t duration = 0;
    if (stream->nb_frames > 0 && stream->duration > 0) {
        this->length = stream->nb_frames;
        duration = stream->duration;
    } else {
        // The video container header doesn't record frame count and/or duration :(
        // Parse video and count frames & accumulate duration.
        // Takes up to ~1 second per hour of video.
        log_info(
            "%s: video frame count and/or duration not in metadata, counting manually",
            this->filename.c_str());
        while (LibAV::read_frame(this->av->demuxer, this->av->packet) >= 0) {
            if (this->av->packet->stream_index == this->video_stream) {
                this->length++;
                duration += this->av->packet->duration;
            }
            LibAV::packet_unref(this->av->packet);
        }
    }
    this->cache.video_length = this->length;
    this->duration_ms =
        ((double)1000.0) * duration * stream->time_base.num / stream->time_base.den;
    return true;
}

void AVS_Video::close() {
    this->close_codec();
    LibAV::close_input(&this->av->demuxer);  // also frees the context
    this->av->demuxer = NULL;
}

void AVS_Video::close_codec() {
    LibAV::free_context(&this->av->decoder);
    LibAV::frame_free(&this->av->frame);
    LibAV::packet_free(&this->av->packet);
    this->av->decoder = NULL;
    this->av->frame = NULL;
    this->av->packet = NULL;
    this->length = 0;
    this->duration_ms = 0;
}

/**
 * The `get_frame()` method and the `cache_frames()` thread interact in the following
 * way. `get_frame()` sets the play head and then lets the decoding-/caching thread
 * know that new frames might be needed. If the frame is already in the cache,
 * `get_frame()` doesn't wait and returns the frame. Meanwhile, the decoder got to work
 * and as soon as the current play head is in the cache, if it wasn't before, a signal
 * is sent back to the waiting `get_frame()` which now returns the frame. The decoding
 * loop continues until the frame cache is filled. Finally, older frames are discarded,
 * and the thread waits for another "need frames" signal.
 *
 * This is a high-level overview and glosses over details such as the necessary locking
 * or cache reset on output format change or `clamp_to_cache` etc.
 *
 *     ┌─────────────┐                           ┌────────────────┐
 *     │ get_frame() │                           │ cache_frames() │
 *     └─────────────┘                           └────────────────┘
 *           │
 *           ▼
 *      set play head
 *           │                                            ┌────────────────┐
 *           ▼                                            ▼                │
 *        [signal]►──────── need frames ───────────────►[wait]             │
 *           │                                            │                │
 *    ───────▼──────────                        ──────────▼─────────────   │
 *    is frame in cache?                        is frame in cache range?   │
 *    ───YES───NO───────                        ─────────YES────NO──────   │
 *        │    │                                          │     │          │
 *        │    │                                          │     ▼          │
 *        │    │                                          │ seek to frame  │
 *        │    │                                          │  clear cache   │
 *        │    │                    ┌──────────────┐      ├─────┘          │
 *        │    │                    │          ────▼──────▼────            │
 *        │    │                    │          is cache filled?            │
 *        │    │                    │          ────NO────YES───            │
 *        │    │                    │              │      │                │
 *        │    │                    │              ▼      │                │
 *        │    │                    │     decode a frame  │                │
 *        │    │                    │              │      │                ▲
 *        │    │                    │     ─────────▼───   │                │
 *        │    │                    │     decoded frame   │                │
 *        │    │                    │     >= play head?   │                │
 *        │    │                    ▲     ──NO────YES──   │                │
 *        │    │                    ├───────┘      │      │                │
 *        │    │                    └───[signal]───┘      │                │
 *        │    │                           ▼              ▼                │
 *        │  [wait]◄── frames available ───┘      prune backward cache     │
 *        └─┬──┘                                          └────────────────┘
 *          │
 *          ▼
 *     return frame
 */

AVS_Video::Frame* AVS_Video::get_frame(int64_t frame_index,
                                       int32_t wanted_width,
                                       int32_t wanted_height,
                                       AVS_Pixel_Format pixel_format,
                                       AVS_Video::Scale scale_mode,
                                       bool clamp_to_cache) {
    if (!this->av->loaded) {
        return NULL;
    }
    frame_index = this->wrap_frame_index(frame_index);
    lock_lock(this->playback_lock);
    if (clamp_to_cache && this->cache.size() > 0) {
        frame_index = this->cache.nearest_cached_frame_index(frame_index);
    }
    this->play_head = frame_index;

    Output_Format new_format = {pixel_format, wanted_width, wanted_height, scale_mode};
    if (new_format != this->output_format) {
        this->output_format = new_format;
        this->cache.reset(this->play_head);
    }
    lock_unlock(this->playback_lock);

    signal_unset(this->frames_available);
    signal_set(this->need_frames);
    if (!this->cache.is_frame_in_cache(this->play_head)) {
        if (signal_wait(this->frames_available, WAIT_FRAMES_AVAILABLE) == NULL) {
            this->error = "timed out waiting for frame";
            return NULL;
        }
    }
    return this->cache.get_frame(this->play_head);
}

bool AVS_Video::cache_frames() {
    signal_t* need_frames_or_stop[2] = {this->need_frames, this->stop_caching};
    auto signalled = signal_wait_any(need_frames_or_stop, 2, WAIT_NEED_FRAMES_OR_STOP);
    if (signalled == NULL) {
        return true;
    } else if (signalled == this->stop_caching) {
        return false;
    }

    lock_lock(this->playback_lock);
    if (!this->cache.is_frame_in_cache_range(this->play_head)) {
        this->seek(this->play_head - this->cache.backward_length);
        this->cache.reset(this->play_head);
    }
    lock_unlock(this->playback_lock);

    bool available_signalled = false;
    while (!this->cache.is_filled(this->play_head)) {
        lock_lock(this->playback_lock);
        this->next_frame();
        if (!available_signalled && this->play_head >= this->cache.start
            && this->play_head < this->cache.start + this->cache.size()) {
            signal_set(this->frames_available);
            available_signalled = true;
        }
        lock_unlock(this->playback_lock);
    }
    this->cache.prune(this->play_head);
    return true;
}

bool AVS_Video::next_frame() {
    int response;
    bool success = false;
    if (this->pf_status == PF_STATUS_HAVE_FRAME) {
        success = this->frame_from_packet();
        LibAV::packet_unref(this->av->packet);
        if (this->pf_status != PF_STATUS_NEXT_PACKET) {
            return success;
        }
    }
    while (true) {
        int read_frame_result = LibAV::read_frame(this->av->demuxer, this->av->packet);
        if (read_frame_result == AVERROR_EOF || this->pf_status == PF_STATUS_EOF) {
            LibAV::seek_frame(this->av->demuxer, -1, 0, 0);
            continue;
        }
        if (this->av->packet->stream_index == this->video_stream) {
            response = LibAV::send_packet(this->av->decoder, this->av->packet);
            if (response < 0) {
                this->error = "packet decode failed (send)";
                this->pf_status = PF_STATUS_ERROR;
                return false;
            }
            success = this->frame_from_packet();
            if (success && this->pf_status == PF_STATUS_NEXT_PACKET) {
                continue;
            }
            return success;
        } else {
            this->pf_status = PF_STATUS_NEXT_PACKET;
        }
        LibAV::packet_unref(this->av->packet);
        if (this->pf_status != PF_STATUS_NEXT_PACKET) {
            break;
        }
    }
    return success;
}

bool AVS_Video::frame_from_packet() {
    int response = 0;
    while (response >= 0) {
        response = LibAV::receive_frame(this->av->decoder, this->av->frame);
        if (response == AVERROR_EOF) {
            this->pf_status = PF_STATUS_EOF;
            return false;
        } else if (response == AVERROR(EAGAIN)) {
            this->pf_status = PF_STATUS_NEXT_PACKET;
            return true;
        } else if (response < 0) {
            this->error = "packet decode failed (recv)";
            this->pf_status = PF_STATUS_ERROR;
            return false;
        }
        this->pf_status = PF_STATUS_HAVE_FRAME;
        if (!this->resample_and_cache_frame()) {
            return false;
        }
        LibAV::frame_unref(this->av->frame);
        return true;
    }
    return false;
}

bool AVS_Video::resample_and_cache_frame() {
    if (!this->recreate_resampler_if_needed()) {
        return false;
    }
    auto stream = this->av->demuxer->streams[this->video_stream];
    auto frame_time_ms =
        1000 * this->av->frame->pts * stream->time_base.num / stream->time_base.den;
    bool is_upside_down = this->av->frame->linesize[0] < 0;
    Frame& new_frame = this->cache.new_frame(this->resampler.dest.pixel_format,
                                             this->resampler.dest.width,
                                             this->resampler.dest.height,
                                             frame_time_ms,
                                             is_upside_down);
    if (new_frame.data == NULL) {
        this->error = "out of memory for new cache frame";
        return false;
    }
    uint8_t* dest_bufs[4] = {(uint8_t*)new_frame.data, NULL, NULL, NULL};
    auto dest_linesize = this->resampler.dest.width
                         * (int32_t)pixel_size(this->resampler.dest.pixel_format);
    const int dest_linesizes[4] = {dest_linesize, 0, 0, 0};
    LibAV::scale(this->av->scaler,
                 this->av->frame->data,
                 this->av->frame->linesize,
                 0,
                 this->av->frame->height,
                 dest_bufs,
                 dest_linesizes);
    return true;
}

bool AVS_Video::recreate_resampler_if_needed() {
    Output_Format dest_format = this->output_format;
    if (this->output_format.width <= 0 && this->output_format.height <= 0) {
        dest_format.width = this->av->frame->width;
        dest_format.height = this->av->frame->height;
    } else if (this->output_format.width <= 0) {
        dest_format.height = this->output_format.height;
        dest_format.width = this->av->frame->width * this->output_format.height
                            / this->av->frame->height;
    } else if (this->output_format.height <= 0) {
        dest_format.width = this->output_format.width;
        dest_format.height = this->av->frame->height * this->output_format.width
                             / this->av->frame->width;
    } else {
        dest_format.width = this->output_format.width;
        dest_format.height = this->output_format.height;
    }
    if (this->resampler.src_width != this->av->frame->width
        || this->resampler.src_height != this->av->frame->height
        || this->resampler.dest != dest_format) {
        this->resampler.src_width = this->av->frame->width;
        this->resampler.src_height = this->av->frame->height;
        this->resampler.dest = dest_format;
        // libavdecode emits pixel formats that are deprecated in libswscale.
        // Transform them here to the new versions, to prevent a noisy warning output.
        AVPixelFormat src_pixel_format;
        switch (this->av->decoder->pix_fmt) {
            case AV_PIX_FMT_YUVJ420P: src_pixel_format = AV_PIX_FMT_YUV420P; break;
            case AV_PIX_FMT_YUVJ422P: src_pixel_format = AV_PIX_FMT_YUV422P; break;
            case AV_PIX_FMT_YUVJ444P: src_pixel_format = AV_PIX_FMT_YUV444P; break;
            case AV_PIX_FMT_YUVJ440P: src_pixel_format = AV_PIX_FMT_YUV440P; break;
            default: src_pixel_format = this->av->decoder->pix_fmt; break;
        }
        AVPixelFormat dest_pixel_format;
        switch (this->resampler.dest.pixel_format) {
            default:
            case AVS_PIXEL_RGB0_8: dest_pixel_format = AV_PIX_FMT_BGRA; break;
        }
        int scaling;
        switch (this->resampler.dest.scale_mode) {
            default:
            case AVS_Video::SCALE_NEAREST: scaling = SWS_POINT; break;
            case AVS_Video::SCALE_FAST_BILINEAR: scaling = SWS_FAST_BILINEAR; break;
            case AVS_Video::SCALE_BILINEAR: scaling = SWS_BILINEAR; break;
            case AVS_Video::SCALE_BICUBIC: scaling = SWS_BICUBIC; break;
            case AVS_Video::SCALE_SPLINE: scaling = SWS_SPLINE; break;
        }
        LibAV::freeContext(this->av->scaler);
        this->av->scaler = LibAV::getContext(this->resampler.src_width,
                                             this->resampler.src_height,
                                             src_pixel_format,
                                             this->resampler.dest.width,
                                             this->resampler.dest.height,
                                             dest_pixel_format,
                                             scaling,
                                             NULL,
                                             NULL,
                                             0);
        if (this->av->scaler == NULL) {
            this->error = "scaler context alloc failed";
            return false;
        }
    }
    return true;
}

bool AVS_Video::copy(Frame* src, void* dest, AVS_Pixel_Format pixel_format) {
    (void)pixel_format;  // TODO [clean]: Remove when adding more pixel formats.
    if (src == NULL || src->data == NULL) {
        return false;
    }
    // TODO [feature]: Make this ready for different pixel formats
    pixel_rgb0_8* src_data = (pixel_rgb0_8*)src->data;
    pixel_rgb0_8* dest_data = (pixel_rgb0_8*)dest;
    if (src->is_upside_down) {
        auto line_length = src->width * pixel_size(pixel_format);
        auto src_end = src->width * (src->height - 1);
        for (int line = 0; line < src->height * src->width; line += src->width) {
            memcpy(&dest_data[line], &src_data[src_end - line], line_length);
        }
    } else {
        memcpy(
            dest_data, src_data, src->height * src->width * pixel_size(pixel_format));
    }
    return true;
}

bool AVS_Video::copy_with_aspect_ratio(Frame* src,
                                       void* dest,
                                       int32_t dest_w,
                                       int32_t dest_h,
                                       AVS_Pixel_Format pixel_format,
                                       void* background) {
    (void)pixel_format;  // TODO [clean]: Remove when adding more pixel formats.
    if (src == NULL || src->data == NULL) {
        return false;
    }
    int32_t src_x_start = 0;
    int32_t src_x_length = src->width;
    int32_t src_y_start = 0;
    int32_t dest_x_start = 0;
    int32_t dest_x_length = dest_w;
    int32_t dest_y_start = 0;
    int32_t diff = 0;
    if (src->width < dest_w) {
        diff = dest_w - src->width;
        dest_x_start = diff / 2;
        dest_x_length = dest_w - diff / 2 + diff % 1;
    } else if (src->width > dest_w) {
        diff = src->width - dest_w;
        src_x_start = diff / 2;
        src_x_length = src->width - diff / 2 + diff % 1;
    }
    if (src->height < dest_h) {
        diff = dest_h - src->height;
        dest_y_start = diff / 2;
    } else if (src->height > dest_h) {
        diff = src->height - dest_h;
        src_y_start = diff / 2;
    }
    auto src_end = src->width * (src->height - 1);
    auto dest_end = dest_w * dest_h;
    // TODO [feature]: Make this ready for different pixel formats
    auto px_size = pixel_size(pixel_format);
    auto line_length = min(src_x_length, dest_x_length) * px_size;
    auto src_data = (pixel_rgb0_8*)src->data;
    auto dest_data = (pixel_rgb0_8*)dest;
    if (background == NULL) {
        if (src->is_upside_down) {
            for (int32_t src_p = src_y_start * src->width - src_x_start,
                         dest_p = dest_y_start * dest_w + dest_x_start;
                 src_p <= src_end && dest_p < dest_end;
                 src_p += src->width, dest_p += dest_w) {
                memcpy(&dest_data[dest_p], &src_data[src_end - src_p], line_length);
            }
        } else {
            for (int32_t src_p = src_y_start * src->width - src_x_start,
                         dest_p = dest_y_start * dest_w + dest_x_start;
                 src_p <= src_end && dest_p < dest_end;
                 src_p += src->width, dest_p += dest_w) {
                memcpy(&dest_data[dest_p], &src_data[src_p], line_length);
            }
        }
    } else {
        auto background_color = (pixel_rgb0_8*)background;
        int32_t src_p;
        int32_t dest_p;
        for (dest_p = 0; dest_p < dest_y_start * dest_w; dest_p += dest_w) {
            for (int32_t x = 0; x < dest_w; x++) {
                memcpy(&dest_data[dest_p + x], background_color, px_size);
            }
        }
        if (src->is_upside_down) {
            for (src_p = src_y_start * src->width - src_x_start,
                dest_p = dest_y_start * dest_w + dest_x_start;
                 src_p <= src_end && dest_p < dest_end;
                 src_p += src->width, dest_p += dest_w) {
                int32_t x;
                for (x = dest_p - dest_x_start; x < dest_p; x++) {
                    memcpy(&dest_data[x], background_color, px_size);
                }
                memcpy(&dest_data[dest_p], &src_data[src_end - src_p], line_length);
                auto dest_line_end = dest_p - dest_x_start + dest_w;
                for (x += src_x_length; x < dest_line_end; x++) {
                    memcpy(&dest_data[x], background_color, px_size);
                }
            }
        } else {
            for (src_p = src_y_start * src->width - src_x_start,
                dest_p = dest_y_start * dest_w + dest_x_start;
                 src_p <= src_end && dest_p < dest_end;
                 src_p += src->width, dest_p += dest_w) {
                int32_t x;
                for (x = dest_p - dest_x_start; x < dest_p; x++) {
                    memcpy(&dest_data[x], background_color, px_size);
                }
                memcpy(&dest_data[dest_p], &src_data[src_p], line_length);
                auto dest_line_end = dest_p - dest_x_start + dest_w;
                for (x += src_x_length; x < dest_line_end; x++) {
                    memcpy(&dest_data[x], background_color, px_size);
                }
            }
        }
        for (; dest_p < dest_end; dest_p += dest_w) {
            for (int32_t x = 0; x < dest_w; x++) {
                memcpy(&dest_data[dest_p + x], background_color, px_size);
            }
        }
    }
    return true;
}

bool AVS_Video::seek(int64_t frame_index) {
    frame_index = max(0, frame_index);
    auto stream = this->av->demuxer->streams[this->video_stream];
    auto result =
        LibAV::seek_frame(this->av->demuxer,
                          this->video_stream,
                          (double)frame_index * stream->duration / this->length,
                          0);
    return result >= 0;
}

size_t AVS_Video::get_video_stream_count() { return this->video_streams.size(); }

bool AVS_Video::set_video_stream(size_t stream_index) {
    auto previous_stream = this->video_stream;
    if (stream_index < this->video_streams.size()) {
        this->video_stream = this->video_streams[stream_index];
        if (this->video_stream != previous_stream) {
            this->cache.reset();
            this->init_codec();
        }
        return true;
    } else {
        return false;
    }
}

int64_t AVS_Video::wrap_frame_index(int64_t frame_index) {
    // The else branch makes the negative modulo behave like a downward continuation of
    // positive modulo. Consider, with length 3:
    //   input:  -3 -2 -1  0  1  2  3
    //   output:  0  1  2  0  1  2  0
    return frame_index >= 0 ? frame_index % this->length
                            : (this->length - 1) + (frame_index + 1) % this->length;
}

void AVS_Video::print_info() {
    auto stream = this->av->demuxer->streams[this->video_stream];
    printf("video stream properties:\n");
    printf("> #frames: %lld\n", stream->nb_frames);
    printf("> timebase: %d/%d\n", stream->time_base.num, stream->time_base.den);
    printf("> start: %lld\n", stream->start_time);
    printf("> duration: %lld\n", stream->duration);
    printf("> avg framerate: %d/%d\n",
           stream->avg_frame_rate.num,
           stream->avg_frame_rate.den);
    printf(">>> duration in ms: %0.3f\n", this->duration_ms);
}

/* Video Frame */

AVS_Video::Frame::Frame(AVS_Pixel_Format pixel_format,
                        int32_t width,
                        int32_t height,
                        int64_t timestamp_ms,
                        bool is_upside_down)
    : timestamp_ms(timestamp_ms), is_upside_down(is_upside_down) {
    if (width > 0 && height > 0) {
        this->pixel_format = pixel_format;
        this->width = width;
        this->height = height;
        this->data = malloc(width * height * pixel_size(pixel_format));
    } else {
        this->pixel_format = AVS_PIXEL_RGB0_8;
        this->width = 0;
        this->height = 0;
        this->data = NULL;
    }
}

AVS_Video::Frame::~Frame() { free(data); }

/* Video Frame Cache */

AVS_Video::Cache::Cache(int64_t max_length,
                        int64_t backward_length,
                        int64_t video_length)
    : max_length(max(1, max_length)),
      backward_length(max(0, backward_length)),
      video_length(video_length),
      lock(lock_init()) {}

AVS_Video::Cache::~Cache() { lock_destroy(this->lock); }

AVS_Video::Frame& AVS_Video::Cache::new_frame(AVS_Pixel_Format pixel_format,
                                              int32_t width,
                                              int32_t height,
                                              int64_t timestamp,
                                              bool is_upside_down) {
    lock_lock(this->lock);
    this->frames.emplace_back(pixel_format, width, height, timestamp, is_upside_down);
    AVS_Video::Frame& out = this->frames.back();
    lock_unlock(this->lock);
    return out;
}

AVS_Video::Frame* AVS_Video::Cache::get_frame(int64_t index) {
    lock_lock(this->lock);
    auto cache_index = this->cache_index(index);
    AVS_Video::Frame* out;
    if (cache_index >= 0 && cache_index < this->frames.size()) {
        out = &this->frames[cache_index];
    } else {
        out = NULL;
    }
    lock_unlock(this->lock);
    return out;
}

void AVS_Video::Cache::prune(int64_t head_index) {
    lock_lock(this->lock);
    auto cache_index = this->cache_index(head_index);
    while (cache_index > this->backward_length && cache_index < this->frames.size()) {
        if (!this->frames.empty()) {
            this->frames.pop_front();
        }
        this->start++;
        if (this->start >= this->video_length) {
            this->start -= this->video_length;
        }
        cache_index = this->cache_index(head_index);
    }
    lock_unlock(this->lock);
}

void AVS_Video::Cache::reset(int64_t head_index) {
    lock_lock(this->lock);
    this->frames.clear();
    this->start = max(0, head_index - this->backward_length);
    lock_unlock(this->lock);
}

size_t AVS_Video::Cache::size() { return this->frames.size(); }

bool AVS_Video::Cache::is_filled(int64_t head_index) {
    lock_lock(this->lock);
    auto forward_length = (int64_t)this->frames.size()
                          - (this->cache_index(head_index) - this->backward_length);
    bool out = forward_length >= this->max_length;
    lock_unlock(this->lock);
    return out;
}

bool AVS_Video::Cache::is_frame_in_cache(int64_t frame_index) {
    lock_lock(this->lock);
    auto cache_index = this->cache_index(frame_index);
    bool out = cache_index >= 0 && cache_index < this->frames.size();
    lock_unlock(this->lock);
    return out;
}

bool AVS_Video::Cache::is_frame_in_cache_range(int64_t frame_index) {
    lock_lock(this->lock);
    auto cache_index = this->cache_index(frame_index);
    bool out = cache_index >= 0
               && (cache_index < this->max_length || cache_index < this->frames.size());
    lock_unlock(this->lock);
    return out;
}

int64_t AVS_Video::Cache::nearest_cached_frame_index(int64_t frame_index) {
    lock_lock(this->lock);
    auto cache_index = this->cache_index(frame_index);
    int64_t out = this->start + cache_index;
    if (cache_index < 0 || cache_index >= this->frames.size()) {
        int64_t split_frame =
            this->frames.size() + max(this->video_length - this->frames.size(), 0) / 2;
        if (cache_index < split_frame) {
            out = this->start + this->frames.size() - 1;
        } else {
            out = this->start;
        }
    }
    while (out >= this->video_length) {
        out -= this->video_length;
    }
    lock_unlock(this->lock);
    return out;
}

int64_t AVS_Video::Cache::cache_index(int64_t frame_index) {
    auto offset = frame_index - this->start;
    return offset < 0 ? offset + this->video_length : offset;
}

AVS_Video::Cache_State AVS_Video::Cache::state() {
    lock_lock(this->lock);
    AVS_Video::Cache_State out = {
        this->size(), this->start, 0, this->max_length, this->backward_length};
    lock_unlock(this->lock);
    return out;
}

AVS_Video::Cache_State AVS_Video::cache_state() {
    auto state = this->cache.state();
    state.play_head = this->play_head;
    return state;
}

#else  // NO_FFMPEG

AVS_Video::AVS_Video(const char*, int64_t, int64_t)
    : error("video support not enabled") {}
AVS_Video::~AVS_Video() {}
AVS_Video::Frame* AVS_Video::get_frame(int64_t,
                                       int32_t,
                                       int32_t,
                                       AVS_Pixel_Format,
                                       AVS_Video::Scale,
                                       bool) {
    return NULL;
}
bool AVS_Video::copy(Frame*, void*, AVS_Pixel_Format) { return false; }
bool AVS_Video::copy_with_aspect_ratio(Frame*,
                                       void*,
                                       int32_t,
                                       int32_t,
                                       AVS_Pixel_Format,
                                       void*) {
    return false;
}
size_t AVS_Video::get_video_stream_count() { return 0; }
bool AVS_Video::set_video_stream(size_t) { return false; }
AVS_Video::Cache_State AVS_Video::cache_state() { return Cache_State(); }

#endif
