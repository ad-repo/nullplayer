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
#pragma once

#include "constants.h"
#include "effect.h"
#include "effect_info.h"

struct Unknown_Config : public Effect_Config {
    std::string id;
    std::string config;
};

struct Unknown_Info : public Effect_Info {
    static constexpr char const* group = "";
    static constexpr char const* name = "Unknown Effect";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -3;
    static constexpr char const* legacy_ape_id = nullptr;

    static constexpr uint32_t num_parameters = 2;
    static constexpr Parameter parameters[num_parameters] = {
        P_STRING(offsetof(Unknown_Config, id), "ID"),
        P_STRING(offsetof(Unknown_Config, config), "Config Data"),
    };

    virtual bool is_createable_by_user() const { return false; }
    EFFECT_INFO_GETTERS;
};

class E_Unknown : public Configurable_Effect<Unknown_Info, Unknown_Config> {
   public:
    E_Unknown(AVS_Instance* avs);
    virtual ~E_Unknown() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load(json& data);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Unknown* clone() { return new E_Unknown(*this); }
    virtual void set_id(int builtin_id, const char* ape_id);

    int legacy_id;
    char legacy_ape_id[LEGACY_APE_ID_LENGTH];
};
