#ifndef FAN_MOTOR_H_
#define FAN_MOTOR_H_

#include "fan_config.h" 


void motor_init(void);
void set_fan_speed(uint8_t state);
uint16_t update_motor_rotation(void);
//extern volatile uint8_t current_servo_pos;

#endif /* FAN_MOTOR_H_ */
