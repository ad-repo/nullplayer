#include <math.h>

// TODO try to use log1p on compatible VS builds

/*void LinearTable(int *table)
{
  for(int i = 0; i < 256; i++)
    table[i] = table[i];  // linear
}*/

void LogBase10Table(int *table)
{
  for(int i = 0; i < 256; i++)
    table[i] = (int)(log10(1.0 + (double)table[i] / 28.3334) * 256.0); // log base 10
}

void LogBase20Table(int *table)
{
  for(int i = 0; i < 256; i++)
    //table[i] = (int)(log(1.0 + (double)table[i] / 13.4211) / log(20.0) * 256.0);   // log base 20
    table[i] = (int)(log1p((double)table[i] / 13.4211) / log(20.0) * 256.0);   // log base 20
}

void LogBase30Table(int *table)
{
  for(int i = 0; i < 256; i++)
    //table[i] = (int)(log(1.0 + (double)table[i] / 8.79311) / log(30.0) * 256.0);   // log base 30
    table[i] = (int)(log1p((double)table[i] / 8.79311) / log(30.0) * 256.0);   // log base 30
}

void LogBase100Table(int *table)
{
  for(int i = 0; i < 256; i++)
    //table[i] = (int)(log(1.0 + (double)table[i] / 2.57576) / log(100.0) * 256.0);   // log base 100
    table[i] = (int)(log1p((double)table[i] / 2.57576) / log(100.0) * 256.0);   // log base 100
}

void NaturalLogTable(int *table)
{
  for(int i = 0; i < 256; i++)
    //table[i] = (int)(log(1.0 + (double)table[i] / 148.4041) * 256.0);   // natural log
    table[i] = (int)(log1p((double)table[i] / 148.4041) * 256.0);   // natural log
}

void SineTable(int *table)
{
  for(int i = 0; i < 256; i++)
    table[i] = (int)(128 + cos(3.141592654 + 0.12 + 3.141592654 * table[i] / 255.0) * 128); // sinus wave
}

void SqrtTable(int *table)
{
  for(int i = 0; i < 256; i++)
    table[i] = (int)(sqrt((double)table[i] * 255.0));  // square root
}

void SqrTable(int *table)
{
  for(int i = 0; i < 256; i++)
    table[i] = (int)((double)(table[i]) / 15.947 * (double)(table[i]) / 15.947);  // squared
}

void FractionalTable(int *table)
{
  for(int i = 0; i < 256; i++)
    table[i] = (int)(256.0 - (double)(256 / (table[i] + 1)));  // 1/x function
}
