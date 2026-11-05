#pragma once

#include "pixel_format.h"

#include "../platform.h"

#include <deque>
#include <string>
#include <vector>

/**
 * A multi-threaded caching auto-looping player class for video files.
 *
 * Load the video instance from the filename and optionally set backward and forward
 * cache sizes. Note that `max_cache_length` is the _complete_ cache, and
 * `backward_cache_length` is only the number of past frames to keep. So with the
 * default of 128 & 64 respectively, 128 total frames will be cached, with 64 frames
 * behind and 64 frames ahead of the current `play_head`. The current frame is
 * considered part of the forward cache, so `max_cache_length` needs to be at least 1,
 * but a minimum of 2 forward frames is recommended. Values less than 1 for
 * `max_cache_length` and 0 for `backward_cache_length` will be silently clamped to 1
 * and 0 respectively!
 *
 * The output format of the frame is dependent on the arguments to `get_frame()`. You
 * can set the required size and pixel format as well as the resampling mode used for
 * scaling.
 *
 * Note that the video frame image data may sometimes be upside down. `copy()` and
 * `copy_with_aspect_ratio()` will take care of this for you, if it is the case.
 *
 * You can use the `cache_state()` method to inspect the current cache state.
 *
 * If AVS was compiled with NO_FFMPEG this class' functions will do nothing and return
 * errors.
 */
class AVS_Video {
   public:
    std::string filename;
    size_t pixel_size;
    int64_t length;
    int64_t play_head;
    double duration_ms;
    const char* error;

    AVS_Video(const char* filename,
              int64_t max_cache_length = 128,
              int64_t backward_cache_length = 64);
    ~AVS_Video();

    struct Frame {
        AVS_Pixel_Format pixel_format;
        void* data;
        int32_t width;
        int32_t height;
        /**
         * A millisecond value denoting when this frame is supposed to be displayed.
         * This value is only meaningful in relation to other frames of the same
         * `AVS_Video` instance.
         */
        int64_t timestamp_ms;
        bool is_upside_down;

        Frame(AVS_Pixel_Format pixel_format,
              int32_t width,
              int32_t height,
              int64_t timestamp_ms,
              bool is_upside_down);
        ~Frame();
    };

    enum Scale {
        SCALE_NEAREST = 0,
        SCALE_FAST_BILINEAR = 1,
        SCALE_BILINEAR = 2,
        SCALE_BICUBIC = 3,
        SCALE_SPLINE = 4,
    };

    /**
     * Sets the playback head of the video to `frame_index` and returns a pointer to
     * that `AVS_Video::Frame` instance. The frame is cached (if it isn't already), and
     * is freed later after you request a frame further ahead than the
     * `backward_cache_length` you set when you created the `AVS_Video` instance.
     *
     * Moving the playback head forward affects the cache: Old frames further back from
     * the head than `backward_cache_length` will be discarded and new frames will be
     * added to the cache, up to a total of `max_cache_length` (including the backward
     * cache).
     *
     * Moving the playback head backwards (within the range of the backward cache),
     * doesn't affect the cache: Previous frames aren't prepended to the backward cache
     * (as video codecs aren't optimized for decoding backwards), and the forward cache
     * doesn't shrink.
     *
     * Moving the playback head outside of the potential cache range will reset the
     * cache completely and the video file will be seeked to the approximate location of
     * the frame. Check the `timestamp_ms` value of the frame to check the actual
     * returned frame.
     *
     * If `clamp_to_cache` is true, requesting a frame will only return frames from the
     * cache. The playback head will be clamped to the end or the beginning of the cache
     * (whichever is nearer) if `frame_index` is outside the cached range. This is
     * useful if you want to add a lot of jitter to your video playback, but still keep
     * the framerate high by avoiding seeking and waiting for frames to be decoded.
     *
     * If `width ≤ 0` and `height ≤ 0` then the result will have the original video's
     * frame size. If only one of `width ≤ 0` or `height ≤ 0` is true the result will be
     * resized to fit this dimension while preserving the aspect ratio of the original.
     * If both are > 0 `frame` will be resized to match, potentially stretching the
     * image.
     *
     * `get_frame()` is not thread-safe. Retrieve frames from a single thread or
     * synchronize carefully. The decoding is already done in a background thread so
     * there should be no speed gains by retrieving frames in parallel.
     *
     * Returns NULL on error. Have a look at the `error` message of the video instance
     * to find out what's wrong.
     */
    Frame* get_frame(int64_t frame_index,
                     int32_t width = 0,
                     int32_t height = 0,
                     AVS_Pixel_Format pixel_format = AVS_PIXEL_RGB0_8,
                     Scale scale_mode = SCALE_NEAREST,
                     bool clamp_to_cache = false);

    /**
     * This function assumes that `dest` has the same dimensions as `src`. Use this when
     * directly scaling/skewing the image to fit AVS' frame size, i.e. after calling
     * `get_frame()` with `dest`'s width and height. `pixel_format` must be the same in
     * both `src` and `dest`.
     */
    bool copy(Frame* src, void* dest, AVS_Pixel_Format pixel_format = AVS_PIXEL_RGB0_8);

    /**
     * This version of `copy()` assumes nothing about the relationship between `src` and
     * `dest` dimensions. It places the video at the center of the window and
     * automatically copies only the overlapping parts of `src` into `dest`.
     * `pixel_format` must be the same in both `src` and `dest`.
     *
     * If you need a background color for the rest of the image, you can pass a pointer
     * to a single pixel with the given pixel format to `background`.
     */
    bool copy_with_aspect_ratio(Frame* src,
                                void* dest,
                                int32_t dest_w,
                                int32_t dest_h,
                                AVS_Pixel_Format pixel_format = AVS_PIXEL_RGB0_8,
                                void* background = NULL);

    /**
     * Very rarely a video file might have more than one video stream. You can use
     * `get_video_stream_count()` to enumerate streams and `set_video_stream()` to
     * select one.
     */
    size_t get_video_stream_count();
    bool set_video_stream(size_t stream_index);

    /**
     * Inspect the current cache state for debugging video playback/caching performance.
     */
    struct Cache_State {
        int64_t size = 0;
        int64_t start = 0;
        int64_t play_head = 0;
        int64_t max_size = 0;
        int64_t backward_length = 0;
    };

    Cache_State cache_state();

#ifndef NO_FFMPEG
   private:
    bool init();
    void close();
    bool init_codec();
    void close_codec();
    static uint32_t frame_cache_thread_func(void* this_video);
    bool cache_frames();
    bool next_frame();
    bool frame_from_packet();
    bool resample_and_cache_frame();
    bool recreate_resampler_if_needed();
    bool seek(int64_t frame_index);
    int64_t wrap_frame_index(int64_t frame_index);
    void print_info();

    struct Cache {
        std::deque<AVS_Video::Frame> frames;
        int64_t start = 0;
        int64_t max_length = 0;
        int64_t backward_length = 0;
        int64_t video_length = 0;
        lock_t* lock = NULL;

        Cache(int64_t max_length, int64_t backward_length, int64_t video_length);
        ~Cache();
        AVS_Video::Frame& new_frame(AVS_Pixel_Format pixel_format,
                                    int32_t width,
                                    int32_t height,
                                    int64_t timestamp,
                                    bool is_upside_down);
        AVS_Video::Frame* get_frame(int64_t index);
        void prune(int64_t head_index);
        void reset(int64_t head_index = 0);
        size_t size();
        bool is_filled(int64_t head_index);
        bool is_frame_in_cache(int64_t frame_index);
        bool is_frame_in_cache_range(int64_t frame_index);
        int64_t nearest_cached_frame_index(int64_t frame_index);
        Cache_State state();

       private:
        // Not thread-safe (and shouldn't be) hence private
        int64_t cache_index(int64_t frame_index);
    };

    struct Output_Format {
        AVS_Pixel_Format pixel_format = AVS_PIXEL_RGB0_8;
        int32_t width = 0;
        int32_t height = 0;
        Scale scale_mode = SCALE_NEAREST;

        inline bool operator==(const Output_Format& other) {
            return this->pixel_format == other.pixel_format
                   && this->width == other.width && this->height == other.height
                   && this->scale_mode == other.scale_mode;
        }
        inline bool operator!=(const Output_Format& other) {
            return !this->operator==(other);
        }
    };

    struct Resample_Info {
        int32_t src_width = 0;
        int32_t src_height = 0;
        Output_Format dest;
    };

    /**
     * A libav packet can have one, multiple or no frames. This tiny state machine keeps
     * track of the current relationship between packets and frames.
     */
    enum Packet_Frame_Status {
        PF_STATUS_NEXT_PACKET,
        PF_STATUS_HAVE_FRAME,
        PF_STATUS_EOF,
        PF_STATUS_ERROR,
    };

    struct LibAV;
    LibAV* av;

    Output_Format output_format;
    Resample_Info resampler;
    Packet_Frame_Status pf_status = PF_STATUS_NEXT_PACKET;
    std::vector<int32_t> video_streams;
    int32_t video_stream = -1;

    Cache cache;
    thread_t* caching_thread = NULL;
    signal_t* need_frames = NULL;
    signal_t* frames_available = NULL;
    signal_t* stop_caching = NULL;
    lock_t* playback_lock = NULL;
#endif
};
