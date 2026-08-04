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
#include "autonomous_drive.h"
#include "bluetooth_control.h"
#include "motor_control.h"
#include "uart_log.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
typedef StaticQueue_t osStaticMessageQDef_t;
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
volatile const char *stack_overflow_task_name = NULL;
volatile uint32_t stack_overflow_count = 0U;
/* USER CODE END Variables */
/* Definitions for Motor */
osThreadId_t MotorHandle;
const osThreadAttr_t Motor_attributes = {
  .name = "Motor",
  .stack_size = 256 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};
/* Definitions for StartSensor */
osThreadId_t StartSensorHandle;
const osThreadAttr_t StartSensor_attributes = {
  .name = "StartSensor",
  .stack_size = 512 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};
/* Definitions for defaultTask */
osThreadId_t defaultTaskHandle;
const osThreadAttr_t defaultTask_attributes = {
  .name = "defaultTask",
  .stack_size = 256 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};
/* Definitions for myMotorQueue */
osMessageQueueId_t myMotorQueueHandle;
uint8_t myMotorQueueBuffer[ 16 * sizeof( MotorMessage ) ];
osStaticMessageQDef_t myMotorQueueControlBlock;
const osMessageQueueAttr_t myMotorQueue_attributes = {
  .name = "myMotorQueue",
  .cb_mem = &myMotorQueueControlBlock,
  .cb_size = sizeof(myMotorQueueControlBlock),
  .mq_mem = &myMotorQueueBuffer,
  .mq_size = sizeof(myMotorQueueBuffer)
};

/* Private function prototypes -----------------------------------------------*/
/* USER CODE BEGIN FunctionPrototypes */

/* USER CODE END FunctionPrototypes */

void Motor_Task(void *argument);
void StartSensor_Task(void *argument);
void StartDefaultTask(void *argument);

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

  /* Create the queue(s) */
  /* creation of myMotorQueue */
  myMotorQueueHandle = osMessageQueueNew (16, sizeof(MotorMessage), &myMotorQueue_attributes);

  /* USER CODE BEGIN RTOS_QUEUES */
  HAL_StatusTypeDef uart_log_status = UartLog_Init();
  MotorControl_Init(myMotorQueueHandle);

  if ((myMotorQueueHandle == NULL) || (uart_log_status != HAL_OK)) {
      Error_Handler();
  }
  /* USER CODE END RTOS_QUEUES */

  /* Create the thread(s) */
  /* creation of Motor */
  MotorHandle = osThreadNew(Motor_Task, NULL, &Motor_attributes);

  /* creation of StartSensor */
  StartSensorHandle = osThreadNew(StartSensor_Task, NULL, &StartSensor_attributes);

  /* creation of defaultTask */
  defaultTaskHandle = osThreadNew(StartDefaultTask, NULL, &defaultTask_attributes);

  /* USER CODE BEGIN RTOS_THREADS */
  /* add threads, ... */
  /* USER CODE END RTOS_THREADS */

  /* USER CODE BEGIN RTOS_EVENTS */
  /* add events, ... */
  /* USER CODE END RTOS_EVENTS */

}

/* USER CODE BEGIN Header_Motor_Task */
/**
* @brief Function implementing the Motor thread.
* @param argument: Not used
* @retval None
*/
/* USER CODE END Header_Motor_Task */
void Motor_Task(void *argument)
{
  /* USER CODE BEGIN Motor_Task */
  MotorControl_Task(argument);
  /* USER CODE END Motor_Task */
}

/* USER CODE BEGIN Header_StartSensor_Task */
/**
* @brief Function implementing the StartSensorTask thread.
* @param argument: Not used
* @retval None
*/
/* USER CODE END Header_StartSensor_Task */
void StartSensor_Task(void *argument)
{
  /* USER CODE BEGIN StartSensor_Task */
  AutonomousDrive_Task(argument);
  /* USER CODE END StartSensor_Task */
}

/* USER CODE BEGIN Header_StartDefaultTask */
/**
* @brief Function implementing the defaultTask thread.
* @param argument: Not used
* @retval None
*/
/* USER CODE END Header_StartDefaultTask */
void StartDefaultTask(void *argument)
{
  /* USER CODE BEGIN StartDefaultTask */
  BluetoothControl_Task(argument);
  /* USER CODE END StartDefaultTask */
}

/* Private application code --------------------------------------------------*/
/* USER CODE BEGIN Application */
void vApplicationStackOverflowHook(TaskHandle_t task, char *task_name)
{
    (void)task;
    stack_overflow_task_name = task_name;
    stack_overflow_count++;
    taskDISABLE_INTERRUPTS();
    for (;;) {
    }
}
/* USER CODE END Application */

