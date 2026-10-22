/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Robust HC-SR04 distance measurement with TIM3 input capture
  ******************************************************************************
  * @attention
  *
  * This version keeps the lecture hardware configuration and separates timeout,
  * overflow-safe pulse calculation, and foreground printing from the ISR.
  *
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
#include <stdio.h>
#include "delay.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
typedef enum
{
  HCSR04_WAIT_RISING = 0,
  HCSR04_WAIT_FALLING
} HCSR04_CaptureState;
/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#ifdef __GNUC__
#define PUTCHAR_PROTOTYPE int __io_putchar(int ch)
#else
#define PUTCHAR_PROTOTYPE int fputc(int ch, FILE *f)
#endif

#define HCSR04_MEASUREMENT_PERIOD_MS 100U
#define HCSR04_ECHO_TIMEOUT_MS        40U
#define HCSR04_MAX_ECHO_US         38000U
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
#define HCSR04_TRIG_PORT GPIOA
#define HCSR04_TRIG_PIN  GPIO_PIN_5
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
static volatile HCSR04_CaptureState captureState = HCSR04_WAIT_RISING;
static volatile uint32_t risingCapture = 0U;
static volatile uint32_t echoPulseUs = 0U;
static volatile uint16_t distanceCm = 0U;
static volatile uint32_t measurementStartTick = 0U;
static volatile uint8_t measurementBusy = 0U;
static volatile uint8_t measurementReady = 0U;
static volatile uint8_t measurementTimedOut = 0U;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */
static void HCSR04_StartMeasurement(void);
static void HCSR04_AbortMeasurement(void);
PUTCHAR_PROTOTYPE;
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
  uint32_t lastTriggerTick = 0U;
  uint32_t nowTick;
  uint32_t pulseSnapshot;
  uint16_t distanceSnapshot;
  uint8_t timeoutSnapshot;
  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_USART2_UART_Init();
  MX_TIM3_Init();
  MX_TIM11_Init();
  /* USER CODE BEGIN 2 */
  /* TIM11의 1 MHz Counter는 10 us Trigger Pulse 생성에 사용합니다. */
  HAL_TIM_Base_Start(&htim11);

  /* TIM3 CH1 Capture는 계속 동작시키되 CC1 Interrupt는 측정할 때만 켭니다. */
  HAL_TIM_IC_Start(&htim3, TIM_CHANNEL_1);
  __HAL_TIM_DISABLE_IT(&htim3, TIM_IT_CC1);
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
    nowTick = HAL_GetTick();

    /* 권장 60 ms보다 긴 100 ms 주기로 새 측정을 시작합니다. */
    if ((measurementBusy == 0U) &&
        ((uint32_t)(nowTick - lastTriggerTick) >= HCSR04_MEASUREMENT_PERIOD_MS))
    {
      lastTriggerTick = nowTick;
      HCSR04_StartMeasurement();
    }

    /* Echo Falling Edge가 오지 않으면 상태를 초기화하고 stale 값을 막습니다. */
    if ((measurementBusy != 0U) &&
        ((uint32_t)(nowTick - measurementStartTick) >= HCSR04_ECHO_TIMEOUT_MS))
    {
      HCSR04_AbortMeasurement();
    }

    if ((measurementReady != 0U) || (measurementTimedOut != 0U))
    {
      /* ISR이 갱신하는 여러 값을 하나의 일관된 Snapshot으로 읽습니다. */
      __disable_irq();
      pulseSnapshot = echoPulseUs;
      distanceSnapshot = distanceCm;
      timeoutSnapshot = measurementTimedOut;
      measurementReady = 0U;
      measurementTimedOut = 0U;
      __enable_irq();

      if (timeoutSnapshot != 0U)
      {
        printf("HC-SR04: out of range or echo timeout\r\n");
      }
      else
      {
        printf("echo = %5luus, distance = %ucm\r\n",
               (unsigned long)pulseSnapshot,
               (unsigned int)distanceSnapshot);
      }
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

  /** Configure the main internal regulator output voltage
  */
  __HAL_RCC_PWR_CLK_ENABLE();
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE1);

  /** Initializes the RCC Oscillators according to the specified parameters in the
  * RCC_OscInitTypeDef structure.
  */
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

  /** Initializes the CPU, AHB and APB buses clocks
  */
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
static void HCSR04_StartMeasurement(void)
{
  measurementBusy = 1U;
  measurementReady = 0U;
  measurementTimedOut = 0U;
  captureState = HCSR04_WAIT_RISING;
  measurementStartTick = HAL_GetTick();

  __HAL_TIM_SET_CAPTUREPOLARITY(&htim3,
                                TIM_CHANNEL_1,
                                TIM_INPUTCHANNELPOLARITY_RISING);
  __HAL_TIM_CLEAR_FLAG(&htim3, TIM_FLAG_CC1);
  __HAL_TIM_ENABLE_IT(&htim3, TIM_IT_CC1);

  /* Trigger를 확실히 Low로 만든 뒤 10 us High Pulse를 출력합니다. */
  HAL_GPIO_WritePin(HCSR04_TRIG_PORT, HCSR04_TRIG_PIN, GPIO_PIN_RESET);
  delay_us(2U);
  HAL_GPIO_WritePin(HCSR04_TRIG_PORT, HCSR04_TRIG_PIN, GPIO_PIN_SET);
  delay_us(10U);
  HAL_GPIO_WritePin(HCSR04_TRIG_PORT, HCSR04_TRIG_PIN, GPIO_PIN_RESET);
}

static void HCSR04_AbortMeasurement(void)
{
  __HAL_TIM_DISABLE_IT(&htim3, TIM_IT_CC1);
  __HAL_TIM_SET_CAPTUREPOLARITY(&htim3,
                                TIM_CHANNEL_1,
                                TIM_INPUTCHANNELPOLARITY_RISING);
  captureState = HCSR04_WAIT_RISING;
  measurementBusy = 0U;
  measurementTimedOut = 1U;
}

void HAL_TIM_IC_CaptureCallback(TIM_HandleTypeDef *htim)
{
  uint32_t fallingCapture;
  uint32_t counterPeriod;
  uint32_t pulseWidth;

  /* 같은 Callback을 사용하는 다른 Timer/Channel의 Event를 제외합니다. */
  if ((htim->Instance != TIM3) ||
      (htim->Channel != HAL_TIM_ACTIVE_CHANNEL_1))
  {
    return;
  }

  if (captureState == HCSR04_WAIT_RISING)
  {
    risingCapture = HAL_TIM_ReadCapturedValue(htim, TIM_CHANNEL_1);
    captureState = HCSR04_WAIT_FALLING;

    __HAL_TIM_SET_CAPTUREPOLARITY(htim,
                                  TIM_CHANNEL_1,
                                  TIM_INPUTCHANNELPOLARITY_FALLING);
  }
  else
  {
    fallingCapture = HAL_TIM_ReadCapturedValue(htim, TIM_CHANNEL_1);
    counterPeriod = __HAL_TIM_GET_AUTORELOAD(htim) + 1U;

    if (fallingCapture >= risingCapture)
    {
      pulseWidth = fallingCapture - risingCapture;
    }
    else
    {
      /* 0..ARR 전체가 한 주기이므로 Wrap 계산에는 ARR+1이 필요합니다. */
      pulseWidth = (counterPeriod - risingCapture) + fallingCapture;
    }

    echoPulseUs = pulseWidth;
    if (pulseWidth <= HCSR04_MAX_ECHO_US)
    {
      distanceCm = (uint16_t)(pulseWidth / 58U);
      measurementReady = 1U;
    }
    else
    {
      measurementTimedOut = 1U;
    }

    captureState = HCSR04_WAIT_RISING;
    measurementBusy = 0U;
    __HAL_TIM_SET_CAPTUREPOLARITY(htim,
                                  TIM_CHANNEL_1,
                                  TIM_INPUTCHANNELPOLARITY_RISING);
    __HAL_TIM_DISABLE_IT(htim, TIM_IT_CC1);
  }
}

PUTCHAR_PROTOTYPE
{
  HAL_UART_Transmit(&huart2, (uint8_t *)&ch, 1U, HAL_MAX_DELAY);
  return ch;
}
/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
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
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
