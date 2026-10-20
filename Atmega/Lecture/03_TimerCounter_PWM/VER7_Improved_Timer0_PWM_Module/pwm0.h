#ifndef PWM0_H_
#define PWM0_H_

#include <stdint.h>

void pwm0Init(void);
void pwm0SetCompare(uint8_t compareValue);
void pwm0SweepUp(void);
void pwm0SweepDown(void);

#endif /* PWM0_H_ */
