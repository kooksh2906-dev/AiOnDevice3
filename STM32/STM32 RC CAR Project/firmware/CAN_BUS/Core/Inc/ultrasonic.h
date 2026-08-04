#ifndef INC_ULTRASONIC_H_
#define INC_ULTRASONIC_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

typedef enum {
    HCSR04_SENSOR_FRONT = 0,
    HCSR04_SENSOR_LEFT  = 1,
    HCSR04_SENSOR_RIGHT = 2,
    HCSR04_SENSOR_COUNT = 3
} HCSR04_Sensor_t;

void HCSR04_BeginMeasurement(HCSR04_Sensor_t sensor);
void HCSR04_ReadSnapshot(uint16_t measured_distance[3], uint8_t valid[3]);

#ifdef __cplusplus
}
#endif

#endif /* INC_ULTRASONIC_H_ */
