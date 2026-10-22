/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : MG996R calibrated PWM control with deferred UART handling
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "tim.h"
#include "usart.h"
#include "gpio.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "servo.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#define SERVO_TIMER_TICK_US     10U
#define SERVO_MIN_PULSE_US     500U
#define SERVO_CENTER_PULSE_US 1500U
#define SERVO_MAX_PULSE_US    2500U
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
static Servo_HandleTypeDef servo;
static uint8_t rxData;
static volatile int16_t requestedAngle;
static volatile uint8_t angleRequestPending;
static volatile uint8_t receivedCommand;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{

  /* USER CODE BEGIN 1 */
  int16_t angleSnapshot;
  uint8_t commandSnapshot;
  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  MX_GPIO_Init();
  MX_USART2_UART_Init();
  MX_TIM3_Init();
  /* USER CODE BEGIN 2 */
  HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1);

  Servo_Init(&servo,
             &htim3,
             TIM_CHANNEL_1,
             SERVO_TIMER_TICK_US,
             SERVO_MIN_PULSE_US,
             SERVO_CENTER_PULSE_US,
             SERVO_MAX_PULSE_US);
  Servo_WriteAngle(&servo, 0);

  HAL_UART_Receive_IT(&huart2, &rxData, sizeof(rxData));
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
    if (angleRequestPending != 0U)
    {
      /* Callback과 공유하는 요청을 짧은 Critical Section에서 가져옵니다. */
      __disable_irq();
      angleSnapshot = requestedAngle;
      commandSnapshot = receivedCommand;
      angleRequestPending = 0U;
      __enable_irq();

      Servo_WriteAngle(&servo, angleSnapshot);

      /* Blocking Echo는 ISR 밖의 Main Context에서 수행합니다. */
      HAL_UART_Transmit(&huart2,
                        &commandSnapshot,
                        sizeof(commandSnapshot),
                        100U);
    }
  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  __HAL_RCC_PWR_CLK_ENABLE();
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE1);

  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_BYPASS;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM = 4;
  RCC_OscInitStruct.PLL.PLLN = 100;
  RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
  RCC_OscInitStruct.PLL.PLLQ = 4;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV2;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_3) != HAL_OK)
  {
    Error_Handler();
  }
}

/* USER CODE BEGIN 4 */
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
  if (huart->Instance == USART2)
  {
    if (rxData == (uint8_t)'a')
    {
      requestedAngle = -90;
      receivedCommand = rxData;
      angleRequestPending = 1U;
    }
    else if (rxData == (uint8_t)'b')
    {
      requestedAngle = 90;
      receivedCommand = rxData;
      angleRequestPending = 1U;
    }
    else if (rxData == (uint8_t)'c')
    {
      requestedAngle = 0;
      receivedCommand = rxData;
      angleRequestPending = 1U;
    }
    else
    {
      /* 정의되지 않은 명령은 위치를 변경하지 않습니다. */
    }

    /* 어떤 Byte가 들어와도 다음 1 Byte 수신을 한 번만 재등록합니다. */
    HAL_UART_Receive_IT(&huart2, &rxData, sizeof(rxData));
  }
}
/* USER CODE END 4 */

void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}

#ifdef USE_FULL_ASSERT
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  (void)file;
  (void)line;
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
