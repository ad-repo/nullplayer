/*
  LICENSE
  -------
Copyright 2005 Nullsoft, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

  * Neither the name of Nullsoft nor the names of its contributors may be used to
    endorse or promote products derived from this software without specific prior
    written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/
#include "e_unknown.h"

#include "constants.h"

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter Unknown_Info::parameters[];

E_Unknown::E_Unknown(AVS_Instance* avs)
    : Configurable_Effect(avs), legacy_id(0), legacy_ape_id() {}

int E_Unknown::render(char[2][2][576], int, int*, int*, int, int) { return 0; }

void E_Unknown::set_id(int builtin_id, const char* ape_id) {
    this->legacy_id = builtin_id;
    memset(this->legacy_ape_id, 0, LEGACY_APE_ID_LENGTH);
    if (ape_id) {
        memcpy(this->legacy_ape_id, ape_id, LEGACY_APE_ID_LENGTH);
    }
}

void E_Unknown::load(json& data) {
    this->enabled = data.value("enabled", true);
    this->comment = Effect_Info::load_string(data.value("comment", json::array()));
    if (data.contains("config")) {
        this->config.id = data.value("effect", "");
        this->config.config =
            data["config"].dump(-1, ' ', false, json::error_handler_t::ignore);
    }
}

void E_Unknown::load_legacy(unsigned char* data, int len) {
    // Need to call `set_id()` first!
    if (this->legacy_ape_id[0] != '\0') {
        this->config.id = std::string(this->legacy_ape_id, LEGACY_APE_ID_LENGTH);
    } else {
        char buf[8];
        memset(buf, 0, sizeof(buf));
        snprintf(buf, 8, "%d", this->legacy_id);
        this->config.id = buf;
    }
    this->config.config = std::string((char*)data, len);
}

int E_Unknown::save_legacy(unsigned char* data) {
    memcpy(data, this->config.config.c_str(), this->config.config.size());
    return (int)this->config.config.size();
}

Effect_Info* create_Unknown_Info() { return new Unknown_Info(); }
Effect* create_Unknown(AVS_Instance* avs) { return new E_Unknown(avs); }
void set_Unknown_desc(char* desc) { E_Unknown::set_desc(desc); }
