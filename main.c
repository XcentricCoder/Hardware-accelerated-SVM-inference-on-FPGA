/*
 * main.c
 *
 *  Created on: 01-Feb-2026
 *      Author: HWSW_14
 */
#include <stdio.h>

#include "data.h"
#include "Xtime_l.h"
#include "svm_model.h"
#include <stdlib.h>
#include "xil_cache.h"


int svm_predict(float *x)
{
	float sum = 0.0f;

	for(int i =0;i<N_FEATURES;i++)
		sum+= svm_w[i]*x[i];

	sum -= svm_b;
	return (sum>=0);
}

int main()
{
    int correct = 0;

    XTime t1, t2;
    XTime_GetTime(&t1);

#define REPEAT 10000

    for(int r=0; r<REPEAT; r++)
    {
        for(int i=0;i<N_SAMPLES;i++)
        {
            int pred = svm_predict(X[i]);
            if(r==0 && pred==y[i])
                correct++;
        }
    }

    XTime_GetTime(&t2);

    double total_time = (double)(t2 - t1) / COUNTS_PER_SECOND;
    total_time /= REPEAT;

    double accuracy   = (double)correct / N_SAMPLES * 100.0;
    double latency    = (total_time / N_SAMPLES) * 1e6;      // microseconds
    double throughput = N_SAMPLES / total_time;              // samples/sec

    /*unsigned char *inData;

    inData = (unsigned char *)malloc(10000);

    int tmp;

    printf("Starting address %0x\n\r ",inData);

    scanf("%d",&tmp);


    Xil_DCacheInvalidate();

    for(int i=0;i<10;i++)
    {
    	printf("%0x %c\\n\r",*inData,*inData);
    	inData++;
	}*/

    printf("\n===== SVM Benchmark =====\n");
    printf("Samples      : %d\n", N_SAMPLES);
    printf("Correct      : %d\n", correct);
    printf("Accuracy     : %.2f %%\n", accuracy);
    printf("Latency      : %.3f us/sample\n", latency);
    printf("Throughput   : %.2f samples/sec\n", throughput);

    while(1);
}
