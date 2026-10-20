#ifndef PWM1_H_
#define PWM1_H_

#include <stdint.h>

void pwm1Init50Hz(void);
void pwm1SetPulseUs(uint16_t pulseWidthUs);

#endif /* PWM1_H_ */
