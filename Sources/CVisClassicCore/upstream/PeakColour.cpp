unsigned char PeakColourFade(const int, const int y)
{
      return (unsigned char)(y); // fade-out
}

unsigned char PeakColourLevel(const int i, const int)
{
      return (unsigned char)i; // colour by level
}

unsigned char PeakColourLevelFade(const int i, const int y)
{
      return (unsigned char)(i - (int)((255 - y) / (255.0 / i)));
}
