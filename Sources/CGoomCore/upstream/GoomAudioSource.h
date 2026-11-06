//
//  GoomAudioSource.h
//  Project
//
//  Created by Jean-Christophe Hoelt on 2/6/12.
//  Copyright (c) 2012 Fovea.cc. All rights reserved.
//

#ifndef Project_GoomAudioSource_h
#define Project_GoomAudioSource_h

class GoomAudioSource {
public:
    virtual ~GoomAudioSource() {}
    virtual void idle(double currentTime) = 0;
    virtual void getSample(short sound[2][512]) const = 0;
};

#endif
