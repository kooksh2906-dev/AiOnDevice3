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
#include "manual_drive.h"
#include "motor_task.h"
#include "uart_log.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
typedef StaticQueue_t osStaticMessageQDef_t;
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#define MOTOR_TASK_PERIOD_MS 20U
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
/* USER CODE BEGIN Variables */
volatile const char *stack_overflow_task_name = NULL;
volatile uint32_t stack_overflow_count = 0U;

/* Motor 태스크만 주행 정책과 출력을 갱신합니다. 다른 태스크는 큐로 요청합니다. */
static ManualDriveState manual_drive;
static uint8_t auto_mode = 0U;
static uint16_t drive_speed = 600U;
static uint16_t mode_generation = 0U;
static MotorControlState applied_motion = {MOTOR_ACTION_STOP, 0U, 0U};
static volatile uint8_t stop_pending = 0U;
static volatile uint8_t pending_stop_command = 0U;

volatile uint32_t motor_msg_count = 0U;
volatile uint32_t motor_user_msg_count = 0U;
volatile uint32_t motor_auto_msg_count = 0U;
volatile uint8_t last_motor_cmd = 0U;
volatile osStatus_t last_motor_submit_status = osOK;
volatile osStatus_t last_motor_queue_get_status = osOK;
volatile uint32_t motor_auto_queue_fail_count = 0U;
volatile uint32_t motor_queue_reset_fail_count = 0U;
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
static void MotorTask_ApplyMotion(const MotorControlState *motion);
static void MotorTask_HandleUserCommand(uint8_t command);
static void MotorTask_SetMode(uint8_t new_mode);
static uint8_t MotorTask_ProcessStopRequest(void);
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
  ManualDrive_Init(&manual_drive, HAL_GetTick());

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
  if ((MotorHandle == NULL) ||
      (StartSensorHandle == NULL) ||
      (defaultTaskHandle == NULL)) {
      Error_Handler();
  }
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
  (void)argument;
  osDelay(1000U);
  MotorControl_Start();

  MotorControlState stop = {MOTOR_ACTION_STOP, 0U, 0U};
  MotorTask_ApplyMotion(&stop);

  for (;;) {
      if (MotorTask_ProcessStopRequest() != 0U) {
          continue;
      }

      MotorMessage message;
      osStatus_t status = osMessageQueueGet(myMotorQueueHandle,
                                             &message,
                                             NULL,
                                             MOTOR_TASK_PERIOD_MS);
      last_motor_queue_get_status = status;

      if (MotorTask_ProcessStopRequest() != 0U) {
          continue;
      }

      if (status == osOK) {
          motor_msg_count++;
          if (message.source == MOTOR_SOURCE_AUTO) {
              motor_auto_msg_count++;
              uint8_t apply;
              taskENTER_CRITICAL();
              apply = (auto_mode != 0U) &&
                      (message.generation == mode_generation);
              taskEXIT_CRITICAL();
              if (apply != 0U) {
                  MotorTask_ApplyMotion(&message.motion);
              }
          } else if (message.source == MOTOR_SOURCE_USER) {
              motor_user_msg_count++;
              last_motor_cmd = message.user_command;
              UartLog_Transmit(&message.user_command, 1U);
              MotorTask_HandleUserCommand(message.user_command);
          }
      }

      if (auto_mode == 0U) {
          ManualDriveOutput output =
              ManualDrive_Update(&manual_drive, HAL_GetTick());
          if (output.valid != 0U) {
              MotorTask_ApplyMotion(&output.motion);
          }
      }
  }
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
/* 큐 전송/수신, 모드 중재와 공유 상태는 FreeRTOS 태스크 계층이 소유합니다. */
static void MotorTask_ApplyMotion(const MotorControlState *motion)
{
    if (MotorControl_Apply(motion) == 0U) {
        return;
    }

    taskENTER_CRITICAL();
    applied_motion = *motion;
    if (motion->action == MOTOR_ACTION_STOP) {
        applied_motion.left_pwm = 0U;
        applied_motion.right_pwm = 0U;
    }
    taskEXIT_CRITICAL();
}

static void MotorTask_SetMode(uint8_t new_mode)
{
    taskENTER_CRITICAL();
    auto_mode = new_mode;
    mode_generation++; /* 이전 모드에서 대기하던 자율 주행 명령 무효화 */
    taskEXIT_CRITICAL();
}

static uint8_t MotorTask_ProcessStopRequest(void)
{
    uint8_t command;
    taskENTER_CRITICAL();
    if (stop_pending == 0U) {
        taskEXIT_CRITICAL();
        return 0U;
    }
    command = pending_stop_command;
    stop_pending = 0U;
    taskEXIT_CRITICAL();

    /* 큐에 남은 오래된 주행 명령을 버린 뒤 모터를 즉시 멈춥니다. */
    if (osMessageQueueReset(myMotorQueueHandle) != osOK) {
        motor_queue_reset_fail_count++;
    }
    motor_msg_count++;
    motor_user_msg_count++;
    last_motor_cmd = command;
    UartLog_Transmit(&command, 1U);
    MotorTask_HandleUserCommand(command);
    return 1U;
}

static void MotorTask_HandleUserCommand(uint8_t command)
{
    MotorControlState stop = {MOTOR_ACTION_STOP, 0U, 0U};
    uint32_t now = HAL_GetTick();

    switch (command) {
    case 'l':
    case 'm':
    case 'h':
        taskENTER_CRITICAL();
        drive_speed = (command == 'l') ? 400U
                    : (command == 'm') ? 600U : 800U;
        taskEXIT_CRITICAL();
        return;

    case 't':
        MotorTask_SetMode(1U);
        ManualDrive_Reset(&manual_drive, now);
        /* 새 센서 판단 전에 전진시키지 않습니다. */
        MotorTask_ApplyMotion(&stop);
        return;

    case 'r':
    case 'S': /* 즉시 정지; 'q'는 기존 수동 감속 명령 */
        MotorTask_SetMode(0U);
        ManualDrive_Reset(&manual_drive, now);
        MotorTask_ApplyMotion(&stop);
        return;

    default:
        break;
    }

    if ((command == 'w') || (command == 'F') ||
        (command == 's') || (command == 'B') ||
        (command == 'a') || (command == 'L') ||
        (command == 'd') || (command == 'R') ||
        (command == 'X')) {
        if (auto_mode != 0U) {
            MotorTask_SetMode(0U);
            ManualDrive_Reset(&manual_drive, now);
            MotorTask_ApplyMotion(&stop);
        }
    }

    if (auto_mode == 0U) {
        ManualDriveOutput output =
            ManualDrive_HandleCommand(&manual_drive, command, drive_speed, now);
        if (output.valid != 0U) {
            MotorTask_ApplyMotion(&output.motion);
        }
    }
}

osStatus_t MotorTask_SubmitUserCommand(uint8_t command)
{
    MotorMessage message = {
        .source = MOTOR_SOURCE_USER,
        .user_command = command
    };
    osStatus_t status;

    if (myMotorQueueHandle == NULL) {
        return osErrorParameter;
    }

    if ((command == 'r') || (command == 'S')) {
        /* 이 CMSIS-FreeRTOS 포트는 메시지 우선순위를 무시하므로 정지는
         * 큐 대신 태스크가 확인하는 요청 플래그로 전달합니다. */
        taskENTER_CRITICAL();
        pending_stop_command = command;
        stop_pending = 1U;
        taskEXIT_CRITICAL();
        last_motor_submit_status = osOK;
        return osOK;
    }

    status = osMessageQueuePut(myMotorQueueHandle, &message, 0U, 0U);
    last_motor_submit_status = status;
    return status;
}

osStatus_t MotorTask_QueueAutoMotion(MotorAction action,
                                     uint16_t left_pwm,
                                     uint16_t right_pwm)
{
    MotorMessage message = {
        .source = MOTOR_SOURCE_AUTO,
        .motion = {(uint8_t)action, left_pwm, right_pwm}
    };
    osStatus_t status;

    if (myMotorQueueHandle == NULL) {
        return osErrorParameter;
    }

    taskENTER_CRITICAL();
    if (auto_mode == 0U) {
        taskEXIT_CRITICAL();
        return osErrorResource;
    }
    message.generation = mode_generation;
    taskEXIT_CRITICAL();

    status = osMessageQueuePut(myMotorQueueHandle, &message, 0U, 0U);
    if (status != osOK) {
        motor_auto_queue_fail_count++;
    }
    return status;
}

uint8_t MotorTask_IsAutoMode(void)
{
    uint8_t mode;
    taskENTER_CRITICAL();
    mode = auto_mode;
    taskEXIT_CRITICAL();
    return mode;
}

uint16_t MotorTask_GetSpeed(void)
{
    uint16_t speed;
    taskENTER_CRITICAL();
    speed = drive_speed;
    taskEXIT_CRITICAL();
    return speed;
}

void MotorTask_GetState(MotorControlState *out_state)
{
    if (out_state == NULL) {
        return;
    }
    taskENTER_CRITICAL();
    *out_state = applied_motion;
    taskEXIT_CRITICAL();
}
/* USER CODE END Application */
