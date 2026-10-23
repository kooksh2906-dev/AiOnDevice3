/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Calibrated two-axis joystick using ADC circular DMA
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "adc.h"
#include "dma.h"
#include "usart.h"
#include "gpio.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include <stdio.h>
#include "joystick.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#define JOYSTICK_AXIS_COUNT 2U
#define JOYSTICK_X_INDEX 0U
#define JOYSTICK_Y_INDEX 1U
#define JOYSTICK_CENTER_SAMPLE_COUNT 32U
#define JOYSTICK_CENTER_SAMPLE_INTERVAL_MS 5U
#define JOYSTICK_DEAD_ZONE 150U
#define JOYSTICK_UPDATE_INTERVAL_MS 10U
#define JOYSTICK_PRINT_INTERVAL_MS 100U

#ifdef __GNUC__
#define PUTCHAR_PROTOTYPE int __io_putchar(int ch)
#else
#define PUTCHAR_PROTOTYPE int fputc(int ch, FILE *f)
#endif
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
volatile uint16_t adcDma[JOYSTICK_AXIS_COUNT];
static Joystick_HandleTypeDef joystick;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */
PUTCHAR_PROTOTYPE;
static void ADC_CopyStablePair(uint16_t *x, uint16_t *y);
/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

int main(void)
{
  /* USER CODE BEGIN 1 */
  uint32_t currentTick;
  uint32_t lastUpdateTick = 0U;
  uint32_t lastPrintTick = 0U;
  uint32_t sumX = 0U;
  uint32_t sumY = 0U;
  uint16_t sampleX;
  uint16_t sampleY;
  uint16_t sampleIndex;
  Joystick_StateTypeDef joystickState = {0};
  /* USER CODE END 1 */

  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  MX_GPIO_Init();
  MX_DMA_Init();
  MX_USART2_UART_Init();
  MX_ADC1_Init();
  /* USER CODE BEGIN 2 */
  if (HAL_ADC_Start_DMA(&hadc1,
                        (uint32_t *)adcDma,
                        JOYSTICK_AXIS_COUNT) != HAL_OK)
  {
    Error_Handler();
  }

  /* Stick을 놓은 상태에서 중심값을 평균 냅니다. */
  HAL_Delay(10U);
  for (sampleIndex = 0U;
       sampleIndex < JOYSTICK_CENTER_SAMPLE_COUNT;
       sampleIndex++)
  {
    ADC_CopyStablePair(&sampleX, &sampleY);
    sumX += sampleX;
    sumY += sampleY;
    HAL_Delay(JOYSTICK_CENTER_SAMPLE_INTERVAL_MS);
  }

  Joystick_Init(&joystick,
                (uint16_t)(sumX / JOYSTICK_CENTER_SAMPLE_COUNT),
                (uint16_t)(sumY / JOYSTICK_CENTER_SAMPLE_COUNT),
                JOYSTICK_DEAD_ZONE);

  printf("Joystick center X=%u, Y=%u\r\n",
         (unsigned int)joystick.centerX,
         (unsigned int)joystick.centerY);
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
    currentTick = HAL_GetTick();

    if ((uint32_t)(currentTick - lastUpdateTick) >=
        JOYSTICK_UPDATE_INTERVAL_MS)
    {
      lastUpdateTick = currentTick;
      ADC_CopyStablePair(&sampleX, &sampleY);
      Joystick_Update(&joystick, sampleX, sampleY, &joystickState);
    }

    if ((uint32_t)(currentTick - lastPrintTick) >=
        JOYSTICK_PRINT_INTERVAL_MS)
    {
      lastPrintTick = currentTick;
      printf("raw X=%4u Y=%4u, normalized X=%5d Y=%5d\r\n",
             (unsigned int)joystickState.rawX,
             (unsigned int)joystickState.rawY,
             (int)joystickState.normalizedX,
             (int)joystickState.normalizedY);
    }
  }
  /* USER CODE END 3 */
}

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
static void ADC_CopyStablePair(uint16_t *x, uint16_t *y)
{
  uint16_t firstX;
  uint16_t firstY;
  uint16_t secondX;
  uint16_t secondY;
  uint8_t retry = 0U;

  if ((x == NULL) || (y == NULL))
  {
    return;
  }

  /* Circular DMA 갱신 도중 서로 다른 Sequence가 섞일 가능성을 줄입니다. */
  do
  {
    firstX = adcDma[JOYSTICK_X_INDEX];
    firstY = adcDma[JOYSTICK_Y_INDEX];
    secondX = adcDma[JOYSTICK_X_INDEX];
    secondY = adcDma[JOYSTICK_Y_INDEX];
    retry++;
  } while (((firstX != secondX) || (firstY != secondY)) && (retry < 4U));

  *x = secondX;
  *y = secondY;
}

PUTCHAR_PROTOTYPE
{
#ifdef __GNUC__
  HAL_UART_Transmit(&huart2, (uint8_t *)&ch, 1U, HAL_MAX_DELAY);
#else
  (void)f;
  HAL_UART_Transmit(&huart2, (uint8_t *)&ch, 1U, HAL_MAX_DELAY);
#endif
  return ch;
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

