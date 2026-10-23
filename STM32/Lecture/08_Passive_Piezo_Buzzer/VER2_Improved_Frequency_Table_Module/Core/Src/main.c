/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Passive piezo buzzer frequency-table PWM control
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
#include "buzzer.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#define BUZZER_TIMER_CLOCK_HZ 100000000U
#define BUZZER_DUTY_PERMILLE        500U

#define NOTE_REST  0U
#define NOTE_A4  440U
#define NOTE_B4  494U
#define NOTE_C5  523U
#define NOTE_D5  587U
#define NOTE_E5  659U
#define NOTE_FS5 740U
#define NOTE_G5  784U
#define NOTE_A5  880U

#define T_8 150U
#define T_4 300U
#define T_2 600U
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
#define ARRAY_SIZE(array) (sizeof(array) / sizeof((array)[0]))
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
static Buzzer_HandleTypeDef buzzer;

static const BuzzerNote_t washingMachineMelody[] = {
  /* [1절] 레 솔 파# 미 레 시 */
  {NOTE_D5,  T_4, 20U}, {NOTE_G5,  T_4, 20U},
  {NOTE_FS5, T_8, 20U}, {NOTE_E5,  T_8, 20U},
  {NOTE_D5,  T_4, 20U}, {NOTE_B4,  T_2, 20U},
  {NOTE_REST, 50U, 0U},

  /* [2절] 도 레 미 라 시 도 시 레 */
  {NOTE_C5, T_4, 20U}, {NOTE_D5, T_4, 20U},
  {NOTE_E5, T_4, 20U}, {NOTE_A4, T_4, 20U},
  {NOTE_B4, T_8, 20U}, {NOTE_C5, T_8, 20U},
  {NOTE_B4, T_4, 20U}, {NOTE_D5, T_4, 20U},

  /* [3절] 레 솔 파# 미 레 솔 */
  {NOTE_D5,  T_4, 20U}, {NOTE_G5, T_4, 20U},
  {NOTE_FS5, T_8, 20U}, {NOTE_E5, T_8, 20U},
  {NOTE_D5,  T_4, 20U}, {NOTE_G5, T_2, 20U},
  {NOTE_REST, 50U, 0U},

  /* [4절] 솔 라 솔 파# 미 파# 솔 */
  {NOTE_G5,  T_8, 20U}, {NOTE_A5,  T_8, 20U},
  {NOTE_G5,  T_8, 20U}, {NOTE_FS5, T_4, 20U},
  {NOTE_E5,  T_8, 20U}, {NOTE_FS5, T_8, 20U},
  {NOTE_G5,  T_2,  0U}
};
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

int main(void)
{
  /* USER CODE BEGIN 1 */
  uint8_t melodyPlayed = 0U;
  /* USER CODE END 1 */

  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  MX_GPIO_Init();
  MX_USART2_UART_Init();
  MX_TIM4_Init();
  /* USER CODE BEGIN 2 */
  if (Buzzer_Init(&buzzer,
                  &htim4,
                  TIM_CHANNEL_1,
                  BUZZER_TIMER_CLOCK_HZ,
                  BUZZER_DUTY_PERMILLE) != HAL_OK)
  {
    Error_Handler();
  }

  if (HAL_TIM_PWM_Start(&htim4, TIM_CHANNEL_1) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
    if (melodyPlayed == 0U)
    {
      if (Buzzer_PlayMelody(&buzzer,
                            washingMachineMelody,
                            ARRAY_SIZE(washingMachineMelody)) != HAL_OK)
      {
        Error_Handler();
      }
      melodyPlayed = 1U;
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
