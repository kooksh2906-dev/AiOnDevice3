/* USER CODE BEGIN Header */
/**
 ******************************************************************************
 * File Name          : freertos.c
 * Description        : Code for freertos applications
 ******************************************************************************
 * @attention
 *
 * Copyright (c) 2026 STMicroelectronics.
 * All rights reserved.
 *
 * This software is licensed under terms that can be found in the LICENSE file
 * in the root directory of this software component.
 * If no LICENSE file comes with this software, it is provided AS-IS.
 *
 ******************************************************************************
 */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "FreeRTOS.h"
#include "task.h"
#include "main.h"
#include "cmsis_os.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "lcd_i2c.h"
#include "can_app.h"
#include <stdio.h>
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#define LCD_LINE_LENGTH    16
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
/* USER CODE BEGIN Variables */

/* USER CODE END Variables */
/* Definitions for lcd */
osThreadId_t lcdHandle;
const osThreadAttr_t lcd_attributes = {
		.name = "lcd",
		.stack_size = 256 * 4,
		.priority = (osPriority_t) osPriorityLow,
};

/* Private function prototypes -----------------------------------------------*/
/* USER CODE BEGIN FunctionPrototypes */
void lcd_print_line(uint8_t row, char *str);
static const char *DirectionText(CanDirection_t direction);
/* USER CODE END FunctionPrototypes */

void lcdTask(void *argument);

void MX_FREERTOS_Init(void); /* (MISRA C 2004 rule 8.1) */

/**
 * @brief  FreeRTOS initialization
 * @param  None
 * @retval None
 */
void MX_FREERTOS_Init(void) {
	/* USER CODE BEGIN Init */

	/* USER CODE END Init */

	/* USER CODE BEGIN RTOS_MUTEX */
	/* add mutexes, ... */
	/* USER CODE END RTOS_MUTEX */

	/* USER CODE BEGIN RTOS_SEMAPHORES */
	/* add semaphores, ... */
	/* USER CODE END RTOS_SEMAPHORES */

	/* USER CODE BEGIN RTOS_TIMERS */
	/* start timers, add new ones, ... */
	/* USER CODE END RTOS_TIMERS */

	/* USER CODE BEGIN RTOS_QUEUES */
	/* add queues, ... */
	/* USER CODE END RTOS_QUEUES */

	/* Create the thread(s) */
	/* creation of lcd */
	lcdHandle = osThreadNew(lcdTask, NULL, &lcd_attributes);

	/* USER CODE BEGIN RTOS_THREADS */
	/* add threads, ... */
	/* USER CODE END RTOS_THREADS */

	/* USER CODE BEGIN RTOS_EVENTS */
	/* add events, ... */
	/* USER CODE END RTOS_EVENTS */

}

/* USER CODE BEGIN Header_lcdTask */
/**
 * @brief  Function implementing the lcd thread.
 * @param  argument: Not used
 * @retval None
 */
/* USER CODE END Header_lcdTask */
void lcdTask(void *argument)
{
	/* USER CODE BEGIN lcdTask */
	(void)argument;

	/*
	 * 전원 인가 직후 LCD 안정화 시간
	 */
	osDelay(100);

	/*
	 * I2C LCD 초기화
	 */
	i2c_lcd_init();
	lcd_clear();
	lcd_show_ready();

	osDelay(1000);
	/* Infinite loop */
	for(;;)
	{
		CanVehicleStatus_t status;
		char line1[17];
		char line2[17];

		if (CAN_App_GetLatestStatus(&status) != 0U) {
			uint32_t last_tick = CAN_App_GetLastRxTick();
			uint32_t now = HAL_GetTick();

			if ((now - last_tick) > 1000U) {
				lcd_print_line(0, "CAN SPEED CTRL");
				lcd_print_line(1, "CAN TIMEOUT");
			} else {
				snprintf(line1, sizeof(line1),
						 "SPD:%3u%% F:%3u",
						 status.speed_percent,
						 status.front_distance);

				snprintf(line2, sizeof(line2),
						 "DIR:%-5s A:%3u",
						 DirectionText(status.direction),
						 status.alive_count);

				lcd_print_line(0, line1);
				lcd_print_line(1, line2);
			}
		} else {
			lcd_show_waiting_can();
		}

		osDelay(200);
	}
	/* USER CODE END lcdTask */
}

/* Private application code --------------------------------------------------*/
/* USER CODE BEGIN Application */
static const char *DirectionText(CanDirection_t direction)
{
	switch (direction) {
	case CAN_DIR_STOP:
		return "STOP";
	case CAN_DIR_FORWARD:
		return "FWD";
	case CAN_DIR_LEFT:
		return "LEFT";
	case CAN_DIR_RIGHT:
		return "RIGHT";
	case CAN_DIR_BACK:
		return "BACK";
	case CAN_DIR_AVOID:
		return "AVOID";
	default:
		return "UNK";
	}
}

/* USER CODE END Application */

