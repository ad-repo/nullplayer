//
//  GoomAudioSourceHeartBeat.h
//  Project
//
//  Created by Jean-Christophe Hoelt on 2/6/12.
//  Copyright (c) 2012 Fovea.cc. All rights reserved.
//

#ifndef Project_GoomAudioSourceHeartBeat_h
#define Project_GoomAudioSourceHeartBeat_h

#include "GoomAudioSource.h"

class GoomAudioSourceHeartBeat : public GoomAudioSource {
    double m_lastBeat;
    float m_amplitude;
public:
    GoomAudioSourceHeartBeat();
    virtual ~GoomAudioSourceHeartBeat() {}
    virtual void getSample(short sound[2][512]) const;

    virtual void idle(double currentTime);
};

#endif
