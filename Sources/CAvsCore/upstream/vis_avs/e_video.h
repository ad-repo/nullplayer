#pragma once

#include "effect.h"
#include "effect_info.h"
#include "video.h"

#include "../platform.h"

enum Video_Blend_Modes {
    VIDEO_BLEND_REPLACE = 0,
    VIDEO_BLEND_ADD = 1,
    VIDEO_BLEND_FIFTY_FIFTY = 2,
    VIDEO_BLEND_FIFTY_FIFTY_ONBEAT_ADD = 3,
};

struct Video_Config : public Effect_Config {
    std::string filename;
    int64_t blend_mode = VIDEO_BLEND_FIFTY_FIFTY;
    int64_t on_beat_persist = 6;
    int64_t playback_speed = 0;
    int64_t resampling_mode = AVS_Video::SCALE_BILINEAR;
};

struct Video_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Video";
    static constexpr char const* help = "This effect was formerly known as \"AVI\".";
    static constexpr int32_t legacy_id = 32;
    static constexpr char* legacy_ape_id = NULL;

    static const char* const* video_files(int64_t* length_out);
    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 4;
        static const char* const options[4] = {
            "Replace",
            "Additive",
            "50/50",
            "50/50 + On-Beat Additive",
        };
        return options;
    }
    static const char* const* resampling_modes(int64_t* length_out) {
        *length_out = 5;
        static const char* const options[5] = {
            "Nearest Neighbor",
            "Fast Bilinear",
            "Bilinear",
            "Bicubic",
            "Spline",
        };
        return options;
    }

    static void on_file_change(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 5;
    static constexpr Parameter parameters[num_parameters] = {
        P_RESOURCE(offsetof(Video_Config, filename),
                   "Filename",
                   video_files,
                   NULL,
                   on_file_change),
        P_SELECT(offsetof(Video_Config, blend_mode), "Blend Mode", blend_modes),
        P_IRANGE(offsetof(Video_Config, on_beat_persist), "On-Beat Persistance", 0, 32),
        P_IRANGE(offsetof(Video_Config, playback_speed), "Playback Speed", 0, 1000),
        P_SELECT(offsetof(Video_Config, resampling_mode),
                 "Resampling Mode",
                 resampling_modes),
    };

    EFFECT_INFO_GETTERS;
};

class E_Video : public Configurable_Effect<Video_Info, Video_Config> {
   public:
    E_Video(AVS_Instance* avs);
    virtual ~E_Video();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void on_load();
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Video* clone() { return new E_Video(*this); }

    void find_video_files();
    static void clear_video_files();
    void load_file();
    void close_file();

    static std::vector<std::string> filenames;
    static const char** c_filenames;

    AVS_Video* video;
    bool loaded;
    int64_t frame_index;
    int64_t last_time;
    lock_t* video_file_lock;
};
