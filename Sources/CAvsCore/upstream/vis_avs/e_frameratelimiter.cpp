#include "e_frameratelimiter.h"

#include <chrono>
#include <string.h>
#include <thread>

constexpr Parameter FramerateLimiter_Info::parameters[];

void update_time_diff(Effect* component,
                      const Parameter*,
                      const std::vector<int64_t>&) {
    E_FramerateLimiter* frameratelimiter = (E_FramerateLimiter*)component;
    frameratelimiter->update_time_diff();
}

E_FramerateLimiter::E_FramerateLimiter(AVS_Instance* avs)
    : Configurable_Effect(avs), time_diff(1000 / 30), last_time(this->now()) {}

E_FramerateLimiter::~E_FramerateLimiter() {}

inline int64_t E_FramerateLimiter::now() {
    /* Don't ask me... */
    return std::chrono::time_point_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now())
        .time_since_epoch()
        .count();
}

inline void E_FramerateLimiter::sleep(int32_t duration_ms) {
    std::this_thread::sleep_for(
        std::chrono::duration<int32_t, std::milli>(duration_ms));
}

int E_FramerateLimiter::render(char[2][2][576], int, int*, int*, int, int) {
    auto cur_time = this->now();
    if (cur_time - this->last_time <= this->time_diff) {
        int32_t sleep_time_ms = this->last_time - this->now() + this->time_diff;
        this->sleep(sleep_time_ms);
    }
    this->last_time = this->now();
    return 0;
}

void E_FramerateLimiter::update_time_diff() {
    this->time_diff = 1000 / this->config.limit;
}

void E_FramerateLimiter::load_legacy(unsigned char* data, int len) {
    int32_t* int_data = (int32_t*)data;
    if (len >= 4) {
        this->enabled = int_data[0] != 0;
    } else {
        this->enabled = true;
    }
    if (len >= 8) {
        this->config.limit = int_data[1];
    } else {
        this->config.limit = 30;
    }
    this->update_time_diff();
}

int E_FramerateLimiter::save_legacy(unsigned char* data) {
    int32_t* int_data = (int32_t*)data;
    int_data[0] = this->enabled ? 1 : 0;
    int_data[1] = this->config.limit;
    return 8;
}

Effect_Info* create_FramerateLimiter_Info() { return new FramerateLimiter_Info(); }
Effect* create_FramerateLimiter(AVS_Instance* avs) {
    return new E_FramerateLimiter(avs);
}
void set_FramerateLimiter_desc(char* desc) { E_FramerateLimiter::set_desc(desc); }
