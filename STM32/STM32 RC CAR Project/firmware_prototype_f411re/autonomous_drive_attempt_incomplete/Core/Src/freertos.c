/* USER CODE BEGIN Header */
/**
 ******************************************************************************
 * File Name Name : freertos.c
 * Description    : Code for freertos applications
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
#include "motor.h"
#include "ultrasonic.h"
#include "bluetooth.h"
#include "can_status.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

#define CAN_STATUS_PERIOD_MS 100U

#define SPEED_KMH_40 40U
#define SPEED_KMH_60 60U
#define SPEED_KMH_80 80U

#define SPEED_PWM_40 450U
#define SPEED_PWM_60 650U
#define SPEED_PWM_80 850U

/* USER CODE END PTD */

/* Private variables ---------------------------------------------------------*/
/* USER CODE BEGIN Variables */

volatile float dist_left = 400.0f;
volatile float dist_center = 400.0f;
volatile float dist_right = 400.0f;

static volatile uint8_t selected_speed_kmh = SPEED_KMH_40;
static volatile uint16_t selected_pwm = SPEED_PWM_40;

static volatile uint8_t current_speed_kmh = 0U;
static volatile CanDirection_t current_direction = CAN_DIR_STOP;

static uint32_t last_can_tx_tick = 0U;

extern volatile uint8_t rx_data;

/* USER CODE END Variables */

osThreadId_t defaultTaskHandle;
const osThreadAttr_t defaultTask_attributes = {
  .name = "defaultTask",
  .stack_size = 256 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};
osThreadId_t MotorHandle;
const osThreadAttr_t Motor_attributes = {
  .name = "Motor",
  .stack_size = 256 * 4,
  .priority = (osPriority_t) osPriorityBelowNormal,
};
osThreadId_t BTHandle;
const osThreadAttr_t BT_attributes = {
  .name = "BT",
  .stack_size = 128 * 4,
  .priority = (osPriority_t) osPriorityBelowNormal,
};

/* Private function prototypes -----------------------------------------------*/
/* USER CODE BEGIN FunctionPrototypes */
static void Check_Raw_Button_Command(void);
static uint16_t Get_Soft_PWM(uint16_t base_pwm);
/* USER CODE END FunctionPrototypes */

void USensorTask(void *argument);
void MotorTask(void *argument);
void BTTask(void *argument);

void MX_FREERTOS_Init(void);

void MX_FREERTOS_Init(void) {
  /* USER CODE BEGIN Init */
  /* USER CODE END Init */

  defaultTaskHandle = osThreadNew(USensorTask, NULL, &defaultTask_attributes);
  MotorHandle = osThreadNew(MotorTask, NULL, &Motor_attributes);
  BTHandle = osThreadNew(BTTask, NULL, &BT_attributes);
}

/* USensorTask: 초음파 센서 주기적 측정 */
void USensorTask(void *argument) {
  (void)argument;
  for(;;) {
    dist_center = Get_Center_Distance();
    dist_left = Get_Left_Distance();
    dist_right = Get_Right_Distance();
    osDelay(20);
  }
}

/* MotorTask: 자율주행 알고리즘 및 블루투스 수동 제어 통합 태스크 */
void MotorTask(void *argument) {
  (void)argument;

  const float WALL_CRIT = 3.0f;
  const float WALL_WARN = 25.0f;
  const float SIDE_CRIT = 8.0f;
  const float SIDE_TOLERANCE = 3.0f;

  selected_speed_kmh = SPEED_KMH_40;
  selected_pwm = SPEED_PWM_40;
  current_speed_kmh = 0U;
  current_direction = CAN_DIR_STOP;

  Motor_Init();
  Bluetooth_Init();

  if (CAN_Status_Init() != HAL_OK) {
    Error_Handler();
  }

  Motor_Stop();
  osDelay(500);
  last_can_tx_tick = HAL_GetTick();

  for(;;) {
    Check_Raw_Button_Command();

    uint16_t drive_pwm = selected_pwm;
    uint16_t soft_pwm = Get_Soft_PWM(drive_pwm);

    /* 1. 자율주행 모드 */
    if (auto_mode == 1) {
      if (dist_center < WALL_CRIT) {
        Motor_Backward(drive_pwm);
        current_direction = CAN_DIR_AUTO;
        current_speed_kmh = selected_speed_kmh;
        osDelay(150);

        if (dist_left >= dist_right) {
          Motor_Turn_Left_Spot(drive_pwm);
        } else {
          Motor_Turn_Right_Spot(drive_pwm);
        }
        current_direction = CAN_DIR_AUTO;
        current_speed_kmh = selected_speed_kmh;
        osDelay(200);
      }
      else if (dist_center < WALL_WARN) {
        if (dist_left >= dist_right) {
          Motor_Turn_Left_Spot(drive_pwm);
        } else {
          Motor_Turn_Right_Spot(drive_pwm);
        }
        current_direction = CAN_DIR_AUTO;
        current_speed_kmh = selected_speed_kmh;
      }
      else if (dist_left < SIDE_CRIT) {
        Motor_Steer(drive_pwm, 100U);
        current_direction = CAN_DIR_AUTO;
        current_speed_kmh = selected_speed_kmh;
      }
      else if (dist_right < SIDE_CRIT) {
        Motor_Steer(100U, drive_pwm);
        current_direction = CAN_DIR_AUTO;
        current_speed_kmh = selected_speed_kmh;
      }
      else {
        if ((dist_right - dist_left) > SIDE_TOLERANCE) {
          Motor_Steer(drive_pwm, soft_pwm);
        } else if ((dist_left - dist_right) > SIDE_TOLERANCE) {
          Motor_Steer(soft_pwm, drive_pwm);
        } else {
          Motor_Straight(drive_pwm);
        }
        current_direction = CAN_DIR_AUTO;
        current_speed_kmh = selected_speed_kmh;
      }
    }
    /* 2. 블루투스 수동 조종 모드 */
    else {
      switch (bt_cmd) {
        case '1':
        case 'X':
          selected_speed_kmh = SPEED_KMH_40;
          selected_pwm = SPEED_PWM_40;
          break;
        case '2':
        case 'C':
          selected_speed_kmh = SPEED_KMH_60;
          selected_pwm = SPEED_PWM_60;
          break;
        case '3':
        case 'T':
          selected_speed_kmh = SPEED_KMH_80;
          selected_pwm = SPEED_PWM_80;
          break;
        case 'F':
          Motor_Straight(drive_pwm);
          current_direction = CAN_DIR_FORWARD;
          current_speed_kmh = selected_speed_kmh;
          break;
        case 'B':
          Motor_Backward(drive_pwm);
          current_direction = CAN_DIR_BACKWARD;
          current_speed_kmh = selected_speed_kmh;
          break;
        case 'L':
          Motor_Turn_Left_Spot(drive_pwm);
          current_direction = CAN_DIR_LEFT;
          current_speed_kmh = selected_speed_kmh;
          break;
        case 'R':
          Motor_Turn_Right_Spot(drive_pwm);
          current_direction = CAN_DIR_RIGHT;
          current_speed_kmh = selected_speed_kmh;
          break;
        case 'S':
        default:
          Motor_Stop();
          current_direction = CAN_DIR_STOP;
          current_speed_kmh = 0U;
          break;
      }
    }

    /* 3. CAN 텔레메트리 상태 송신 */
    if ((HAL_GetTick() - last_can_tx_tick) >= CAN_STATUS_PERIOD_MS) {
      (void)CAN_Status_Send(current_speed_kmh, current_direction, dist_center);
      last_can_tx_tick = HAL_GetTick();
    }

    osDelay(20);
  }
}

void BTTask(void *argument) {
  (void)argument;
  for(;;) {
    osDelay(1);
  }
}

static void Check_Raw_Button_Command(void) {
  static uint8_t last_rx_data = 0U;
  uint8_t data = rx_data;

  if (data == last_rx_data) {
    return;
  }
  last_rx_data = data;

  switch (data) {
    case '1':
    case 'X':
      selected_speed_kmh = SPEED_KMH_40;
      selected_pwm = SPEED_PWM_40;
      break;
    case '2':
    case 'C':
      selected_speed_kmh = SPEED_KMH_60;
      selected_pwm = SPEED_PWM_60;
      break;
    case '3':
    case 'T':
      selected_speed_kmh = SPEED_KMH_80;
      selected_pwm = SPEED_PWM_80;
      break;
    case 'P':
    case 'M':
      auto_mode = 0;
      bt_cmd = 'S';
      break;
    case 'A':
      auto_mode = 1;
      break;
    default:
      break;
  }
}

static uint16_t Get_Soft_PWM(uint16_t base_pwm) {
  uint16_t soft_pwm = base_pwm / 2U;
  if (soft_pwm < 100U) {
    soft_pwm = 100U;
  }
  return soft_pwm;
}
