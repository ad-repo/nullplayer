#pragma once

#include "constants.h"
#include "effect.h"
#include "effect_info.h"

#include <stdio.h>
#include <stdlib.h>

struct Root_Contributor_Config : public Effect_Config {
    std::string role = "contributor";
    std::string name;
};

struct Root_BasedOn_Config : public Effect_Config {
    std::string id;
    std::string name;
    std::string date;
    std::vector<Root_Contributor_Config> contributors;
};

struct Root_Config : public Effect_Config {
    bool clear = false;
    std::string name;
    std::string id;
    std::string date_init;
    std::string date_last;
    std::vector<Root_Contributor_Config> contributors;
    std::vector<Root_BasedOn_Config> based_on;
};

struct Root_Info : public Effect_Info {
    static constexpr char const* group = "";
    static constexpr char const* name = "Root";
    static constexpr char const* help =
        "The main component of the preset\n"
        "Define basic settings for the preset here\n";
    static constexpr int32_t legacy_id = -4;
    static constexpr char const* legacy_ape_id = nullptr;

    static constexpr uint32_t num_contributor_parameters = 2;
    static constexpr Parameter contributor_parameters[num_contributor_parameters] = {
        P_STRING(offsetof(Root_Contributor_Config, name),
                 "Name",
                 "Name of the person contributing to the preset"),
        P_STRING(offsetof(Root_Contributor_Config, role),
                 "Role",
                 "'contributor', 'curator', 'author', 'remixer', 'editor' - or "
                 "anything else")};

    static constexpr uint32_t num_remix_parameters = 4;
    static constexpr Parameter remix_parameters[num_remix_parameters] = {
        P_STRING(offsetof(Root_BasedOn_Config, id), "ID", "UUID of the predecessor"),
        P_STRING(offsetof(Root_BasedOn_Config, name),
                 "Name",
                 "Name of the predecessor"),
        P_STRING(offsetof(Root_BasedOn_Config, date),
                 "Date",
                 "Last-edited date of the predecessor"),
        P_LIST<Root_Contributor_Config>(offsetof(Root_BasedOn_Config, contributors),
                                        "Contributors",
                                        contributor_parameters,
                                        num_contributor_parameters,
                                        0,
                                        0,
                                        "Contributors of the predecessor"),
    };

    static constexpr uint32_t num_parameters = 7;
    static constexpr Parameter parameters[num_parameters] = {
        P_BOOL(offsetof(Root_Config, clear),
               "Clear",
               "Clear the screen for every new frame"),
        P_STRING(offsetof(Root_Config, name), "Name", "Name of the preset"),
        P_STRING(offsetof(Root_Config, id), "ID", "UUID of the preset"),
        P_STRING(offsetof(Root_Config, date_init),
                 "Date Initial",
                 "Date of preset's first save"),
        P_STRING(offsetof(Root_Config, date_last),
                 "Date Last",
                 "Date of preset's latest save"),
        P_LIST<Root_Contributor_Config>(offsetof(Root_Config, contributors),
                                        "Contributors",
                                        contributor_parameters,
                                        num_contributor_parameters,
                                        0,
                                        0,
                                        "Contributors of the preset"),
        P_LIST<Root_BasedOn_Config>(offsetof(Root_Config, based_on),
                                    "Based On",
                                    remix_parameters,
                                    num_remix_parameters,
                                    0,
                                    0,
                                    "Previous presets used to create this one"),
    };

    virtual bool can_have_child_components() const { return true; }
    virtual bool is_createable_by_user() const { return false; }
    EFFECT_INFO_GETTERS;
};

class E_Root : public Configurable_Effect<Root_Info, Root_Config> {
   public:
    E_Root(AVS_Instance* avs);
    virtual ~E_Root();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void render_with_context(RenderContext& ctx);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Root* clone() { return new E_Root(*this); }
    void remix();
    int64_t get_num_renders() { return this->children.size(); }
    void start_buffer_context();
    void end_buffer_context();

   private:
    // these are our framebuffers (formerly nb_save)
    int buffers_w[NUM_GLOBAL_BUFFERS] = {};
    int buffers_h[NUM_GLOBAL_BUFFERS] = {};
    void* buffers[NUM_GLOBAL_BUFFERS] = {};

    // these are temp space for saving the global ones (formerly nb_save2)
    int buffers_temp_w[NUM_GLOBAL_BUFFERS] = {};
    int buffers_temp_h[NUM_GLOBAL_BUFFERS] = {};
    void* buffers_temp[NUM_GLOBAL_BUFFERS] = {};

    bool buffers_saved;
};
