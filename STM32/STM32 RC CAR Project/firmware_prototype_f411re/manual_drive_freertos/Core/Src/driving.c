/*
 * driving.c
 *
 *  Created on: 2026. 6. 19.
 *      Author: user
 */

#include "driving.h"
#include "motor.h"
#include "bluetooth.h"

void ModeSelect(){

	if(rx_data == 'A'){
		/* AUTO-MODE MOTOR OPERATING CODE */
		current_mode = AUTO_MODE;
		motor_stop();
	}

	if(rx_data == 'P'){
		/* MANUAL-MODE MOTOR OPERATING CODE */
		current_mode = MANUAL_MODE;
		motor_stop();
	}
}

void BlueToothDriving(){

	if(rx_data == 'F'){
		motor_forward();
	}
	else if(rx_data == 'B'){
		motor_backward();
	}
	else if(rx_data == 'L'){
		motor_left();
	}
	else if(rx_data == 'R'){
		motor_right();
	}
	else if(rx_data == 'X'){
		motor_stop();
	}
	else if(rx_data == 'T'){
		/* SPEED-UP +100 MOTOR OPERATING CODE */
		motor_speed_up();  // 깔끔하게 함수로 호출!
	}
	else if(rx_data == 'S'){
		/* SPEED-DOWN -100 MOTOR OPERATING CODE */
		motor_speed_down(); // 깔끔하게 함수로 호출!
	}
}
