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
//#include "ultrasonic.h"
#include "motor.h"
#include "bluetooth.h"
#include "driving.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
/* USER CODE BEGIN Variables */

/* USER CODE END Variables */
/* Definitions for defaultTask */
osThreadId_t defaultTaskHandle;
const osThreadAttr_t defaultTask_attributes = {
  .name = "defaultTask",
  .stack_size = 128 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};
/* Definitions for BtTask */
osThreadId_t BtTaskHandle;
const osThreadAttr_t BtTask_attributes = {
  .name = "BtTask",
  .stack_size = 128 * 4,
  .priority = (osPriority_t) osPriorityAboveNormal,
};
/* Definitions for AutoTask */
osThreadId_t AutoTaskHandle;
const osThreadAttr_t AutoTask_attributes = {
  .name = "AutoTask",
  .stack_size = 128 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};

/* Private function prototypes -----------------------------------------------*/
/* USER CODE BEGIN FunctionPrototypes */

/* USER CODE END FunctionPrototypes */

void StartDefaultTask(void *argument);
void StartBtTask(void *argument);
void StartAutoTask(void *argument);

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
  /* creation of defaultTask */
  defaultTaskHandle = osThreadNew(StartDefaultTask, NULL, &defaultTask_attributes);

  /* creation of BtTask */
  BtTaskHandle = osThreadNew(StartBtTask, NULL, &BtTask_attributes);

  /* creation of AutoTask */
  AutoTaskHandle = osThreadNew(StartAutoTask, NULL, &AutoTask_attributes);

  /* USER CODE BEGIN RTOS_THREADS */
  /* add threads, ... */
  /* USER CODE END RTOS_THREADS */

  /* USER CODE BEGIN RTOS_EVENTS */
  /* add events, ... */
  /* USER CODE END RTOS_EVENTS */

}

/* USER CODE BEGIN Header_StartDefaultTask */
/**
  * @brief  Function implementing the defaultTask thread.
  * @param  argument: Not used
  * @retval None
  */
/* USER CODE END Header_StartDefaultTask */
void StartDefaultTask(void *argument)
{
  /* USER CODE BEGIN StartDefaultTask */
  /* Infinite loop */
  for(;;)
  {
	  osDelay(1);
  }
  /* USER CODE END StartDefaultTask */
}

/* USER CODE BEGIN Header_StartBtTask */
/**
* @brief Function implementing the BtTask thread.
* @param argument: Not used
* @retval None
*/
/* USER CODE END Header_StartBtTask */
void StartBtTask(void *argument)
{
  /* USER CODE BEGIN StartBtTask */

  /* Infinite loop */
	for(;;)
	{
		if (rx_flag == RX_SET) {
			rx_flag = RX_RESET; // 플래그 끄기
			ModeSelect();       // 모드 체크

			if (current_mode == MANUAL_MODE)
			{
				BlueToothDriving(); // 수동 주행 실행
			}
		}
		osDelay(1);
	}
  /* USER CODE END StartBtTask */
}

/* USER CODE BEGIN Header_StartAutoTask */
/**
* @brief Function implementing the AutoTask thread.
* @param argument: Not used
* @retval None
*/
/* USER CODE END Header_StartAutoTask */
void StartAutoTask(void *argument)
{
  /* USER CODE BEGIN StartAutoTask */
	/* Infinite loop */
	for(;;)
	{
		if (current_mode == AUTO_MODE){
			/* * [나중에 초음파 센서 넣을 자리]
			 * 큐를 쓰지 않고, 여기서 "벽이 감지되었을 때 딱 한 번"
			 * Motor_Control() 함수를 호출할 것이므로 명령이 누적되거나 꼬이지 않습니다.
			 */

			// 우선은 자율주행 모드 테스트를 위해 제자리 회전 돌려놓기
			HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
			osDelay(200);
		}
		else{
			osDelay(10);
		}

	}
  /* USER CODE END StartAutoTask */
}

/* Private application code --------------------------------------------------*/
/* USER CODE BEGIN Application */

/* USER CODE END Application */

