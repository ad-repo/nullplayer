// returns the highest level (stereo)
int UnionLevelCalcStereo(const int low, const int high, const unsigned char *spectrumData)
{
  int newlevel = 0;

  for(int i = low; i < high; i++)
    if(spectrumData[i] > newlevel)
      newlevel = spectrumData[i];

  return newlevel;
}

// returns the highest level (stereo)
int AverageLevelCalcStereo(const int low, const int high, const unsigned char *spectrumData)
{
	int newlevel = 0;

	for(int i = low; i < high; i++)
		newlevel += spectrumData[i];

	return newlevel / (high - low);
}

// returns the highest level (mono)
int UnionLevelCalcMono(const int low, const int high, const unsigned char *spectrumDataLeft, const unsigned char *spectrumDataRight)
{
  int newlevel = 0;

  for(int i = low; i < high; i++) {
    if(spectrumDataLeft[i] > newlevel)
      newlevel = spectrumDataLeft[i];
    if(spectrumDataRight[i] > newlevel)
      newlevel = spectrumDataRight[i];
  }

  return newlevel;
}

// returns the average level (mono)
int AverageLevelCalcMono(const int low, const int high, const unsigned char *spectrumDataLeft, const unsigned char *spectrumDataRight)
{
	int newlevel = 0;

	for(int i = low; i < high; i++) {
		newlevel += spectrumDataLeft[i];
		newlevel += spectrumDataRight[i];
	}

	return newlevel / (2 * (high - low));
}
