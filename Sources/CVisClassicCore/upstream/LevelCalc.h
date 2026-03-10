#ifndef LEVEL_CALC_H
#define LEVEL_CALC_H

int UnionLevelCalcStereo(const int low, const int high, const unsigned char *spectrumData);
int AverageLevelCalcStereo(const int low, const int high, const unsigned char *spectrumData);
int UnionLevelCalcMono(const int low, const int high, const unsigned char *spectrumDataLeft, const unsigned char *spectrumDataRight);
int AverageLevelCalcMono(const int low, const int high, const unsigned char *spectrumDataLeft, const unsigned char *spectrumDataRight);

#endif /* LEVEL_CALC_H */
