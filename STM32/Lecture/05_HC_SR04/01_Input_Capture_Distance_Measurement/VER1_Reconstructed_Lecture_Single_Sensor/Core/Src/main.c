/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : HC-SR04 lecture example reconstructed from class captures
  ******************************************************************************
  * @attention
  *
  * This file preserves the behavior shown in the lecture material while placing
  * user code only in STM32CubeMX USER CODE regions.
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

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#ifdef __GNUC__
#define PUTCHAR_PROTOTYPE int __io_putchar(int ch)
#else
#define PUTCHAR_PROTOTYPE int fputc(int ch, FILE *f)
#endif
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
#define TRIG_PORT GPIOA
#define TRIG_PIN  GPIO_PIN_5
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
uint16_t IC_Value1 = 0U;
uint16_t IC_Value2 = 0U;
uint16_t echoTime = 0U;

uint8_t captureFlag = 0U;
uint8_t distance = 0U;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */
void HCSR04_TRIG(void);
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
  /* TIM11은 delay_us()가 사용하는 1 MHz Free-running Counter입니다. */
  HAL_TIM_Base_Start(&htim11);

  /* TIM3 CH1은 PA6 Echo 신호의 Rising/Falling Edge를 Interrupt로 캡처합니다. */
  HAL_TIM_IC_Start_IT(&htim3, TIM_CHANNEL_1);
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
    HCSR04_TRIG();
    HAL_Delay(500U);

    /* 수업 결과 화면과 같은 형식으로 Capture 값과 계산 거리를 출력합니다. */
    printf("IC_Value1 = %5dus, IC_Value2 = %5dus, distance = %dcm\r\n",
           IC_Value1, IC_Value2, distance);
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
void HCSR04_TRIG(void)
{
  /* HC-SR04는 10 us 이상의 High Pulse가 들어오면 거리 측정을 시작합니다. */
  HAL_GPIO_WritePin(TRIG_PORT, TRIG_PIN, GPIO_PIN_SET);
  delay_us(10U);
  HAL_GPIO_WritePin(TRIG_PORT, TRIG_PIN, GPIO_PIN_RESET);

  /* 이전 측정이 끝날 때 끈 CC1 Interrupt를 다음 측정에 맞춰 다시 켭니다. */
  __HAL_TIM_ENABLE_IT(&htim3, TIM_IT_CC1);
}

void HAL_TIM_IC_CaptureCallback(TIM_HandleTypeDef *htim)
{
  if (htim->Channel == HAL_TIM_ACTIVE_CHANNEL_1)
  {
    if (captureFlag == 0U)
    {
      /* Echo Rising Edge의 Counter 값을 시작 시점으로 저장합니다. */
      IC_Value1 = (uint16_t)HAL_TIM_ReadCapturedValue(&htim3, TIM_CHANNEL_1);
      captureFlag = 1U;

      /* 다음 Capture는 Echo High Pulse가 끝나는 Falling Edge에서 발생합니다. */
      __HAL_TIM_SET_CAPTUREPOLARITY(&htim3,
                                    TIM_CHANNEL_1,
                                    TIM_INPUTCHANNELPOLARITY_FALLING);
    }
    else
    {
      IC_Value2 = (uint16_t)HAL_TIM_ReadCapturedValue(&htim3, TIM_CHANNEL_1);
      __HAL_TIM_SET_COUNTER(&htim3, 0U);

      if (IC_Value2 > IC_Value1)
      {
        echoTime = IC_Value2 - IC_Value1;
      }
      else
      {
        /* 수업 코드의 16-bit Counter Overflow 계산을 그대로 보존했습니다. */
        echoTime = (uint16_t)((0xFFFFU - IC_Value1) + IC_Value2);
      }

      /* 데이터시트의 근사식: Echo High time [us] / 58 = distance [cm]. */
      distance = (uint8_t)(echoTime / 58U);
      captureFlag = 0U;

      __HAL_TIM_SET_CAPTUREPOLARITY(&htim3,
                                    TIM_CHANNEL_1,
                                    TIM_INPUTCHANNELPOLARITY_RISING);
      __HAL_TIM_DISABLE_IT(&htim3, TIM_IT_CC1);
    }
  }
}

PUTCHAR_PROTOTYPE
{
  /* printf() 한 문자를 USART2로 전달하여 ST-LINK VCP/Tera Term에 출력합니다. */
  HAL_UART_Transmit(&huart2, (uint8_t *)&ch, 1U, 0xFFFFU);
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
