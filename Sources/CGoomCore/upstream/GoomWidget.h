//
//  GoomWidget.h
//  Project
//
//  Created by Jean-Christophe Hoelt on 2/5/12.
//  Copyright (c) 2012 Fovea.cc. All rights reserved.
//

#ifndef Project_GoomWidget_h
#define Project_GoomWidget_h

#include "GameTools.h"
#include "GoomAudioSource.h"
#include "goom_typedefs.h"
#include <string>

class GoomWidgetListener {
public:
    virtual ~GoomWidgetListener() {}
    virtual void onCloseGoomWidget() = 0;
};

class GoomWidget : public gametools::ActionContainer
{
    GoomWidgetListener &m_listener;
    GoomAudioSource    *m_source;
    int                 m_goomW, m_goomH;
    PluginInfo         *m_goom;
    char               *m_rgbaBuffer;
    double              m_currentTime;
    double              m_nextFrame;
    std::auto_ptr<gametools::IosSurface> m_goomSurface;
    
    double m_lastFrame;
    float  m_fps;
    bool   m_firstUpdate;
    std::string m_titleText;  // current title (setTitleText); "" = untouched
    bool   m_titleDirty;      // true while m_titleText has not reached goom yet

public:
	GoomWidget(GoomWidgetListener &listener, GoomAudioSource &source, int w, int h);
    ~GoomWidget();
    
    virtual void eventOccured(gametools::event_manager::GameControlEvent *event);
	virtual void action(gametools::Widget *sender, int actionType, gametools::event_manager::GameControlEvent *event);
	virtual void idle(double currentTime);
	virtual void draw(gametools::DrawTarget *dt);
    
    void drawGoom(gametools::DrawTarget *dt, gametools::ImageBlendMode mode, float r, float g, float b, float a);
    
    void setAudioSource(GoomAudioSource &source) { m_source = &source; }
    const GoomAudioSource &getAudioSource() const { return *m_source; }
    GoomAudioSource &getAudioSource() { return *m_source; }

    // Show a spinning title over the visual on the next update (the same
    // path as the first-update "Goom.2k26" string). A NULL or empty title
    // blanks the overlay instead. Trying to show the title that is already
    // current is ignored, so a host app may call this every frame; inert
    // until first called.
    void setTitleText(const char *t);

    // Live PluginInfo for the desktop control server (params UI). Owned here.
    PluginInfo *getGoomInfo() { return m_goom; }
    
private:
    void updateGoom();
};

#endif
