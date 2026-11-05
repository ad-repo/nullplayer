void matrixRotate(float matrix[], char m, float Deg);
void matrixTranslate(float m[], float x, float y, float z);
void matrixMultiply(float* dest, float src[]);
void matrixApply(float* m,
                 float x,
                 float y,
                 float z,
                 float* outx,
                 float* outy,
                 float* outz);
