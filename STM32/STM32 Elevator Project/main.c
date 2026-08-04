/* USER CODE BEGIN Header */
/**
 ******************************************************************************
 * @file           : main.c
 * @brief          : Main program body
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
#include "main.h"
#include "i2c.h"
#include "usart.h"
#include "gpio.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "stdlib.h"
#include "stdio.h"

#ifdef __GNUC__
  /* With GCC, small printf (option LD Linker->Libraries->Small printf
     set to 'Yes') calls __io_putchar() */
  #define PUTCHAR_PROTOTYPE int __io_putchar(int ch)
#else
  #define PUTCHAR_PROTOTYPE int fputc(int ch, FILE *f)
#endif /* __GNUC__ */

PUTCHAR_PROTOTYPE
{
  HAL_UART_Transmit(&huart2, (uint8_t *)&ch, 1, 0xFFFF);
  return ch;
}
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

/* USER CODE BEGIN PV */

/* 도어 모터 제어를 위한 전역 구조체 인스턴스 */
DOOR_CONTROL elevator_door;

/* 시스템 전체의 동작 모드를 결정하는 상태 변수 (초기값: 정상 모드) */
uint8_t state = STATE_NORMAL;

/* UART 터미널 안내 메시지가 무한 반복 출력되는 것을 막기 위한 출력 플래그 */
uint8_t EmergencyMsgflag = MSG_OFF;
uint8_t RecoverMsgflag = MSG_OFF;
uint8_t TestRunMsgflag = MSG_OFF;

/* 모터, 방향, LED 제어에 필요한 비동기 틱(Tick) 및 상태 변수들 */
uint32_t last_motor_time = 0;
uint8_t lift_direction = 0;
int8_t motor_step = 0;
int8_t led_index = 0;
uint32_t last_led_time = 0;

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
  MX_I2C1_Init();
  /* USER CODE BEGIN 2 */

  /* 전원 인가 시 시스템 하드웨어 영점(1층)을 잡고 초기화를 수행합니다. */
  SysInit();
	//Password_Init();
	//door_init(&elevator_door, 2, 1024);

  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */

	while (1)
	{
		// ====================================================================
		      // 1. 정상 동작 상태 (엘리베이터 전체 로직)
		      // ====================================================================
		      if(state == STATE_NORMAL)
		      {
		    	  /* 키패드 및 LCD 비밀번호 입력 로직 지속 업데이트 */
		          Password_Update();

		          // 방향 입력 수신 처리 및 [인터록(안전) 원천 차단]
		          if (buttonGetPressed(0) && !Photo_IsTopBlocked()) // UpLift
		          {
		              lift_direction = 1;
		          }
		          else if (buttonGetPressed(1) && !Photo_IsBottomBlocked()) // DownLift
		          {
		              lift_direction = 2;
		          }
		          else
		          {
		              lift_direction = 0;
		          }

		          // 모터 구동 처리 (2ms)
		          if (HAL_GetTick() - last_motor_time >= 2)
		          {
		              last_motor_time = HAL_GetTick();
		              switch (lift_direction)
		              {
		              case 1:
		                  motor_step++;
		                  if (motor_step >= 8) motor_step = 0;
		                  stepMotor(motor_step);
		                  break;
		              case 2:
		                  motor_step--;
		                  if (motor_step < 0) motor_step = 7;
		                  stepMotor(motor_step);
		                  break;
		              default:
		                  motorStop();
		                  break;
		              }
		          }

		          // LED 시프트 디스플레이 처리 (100ms)
		          if (HAL_GetTick() - last_led_time >= 100)
		          {
		              last_led_time = HAL_GetTick();
		              if (lift_direction == 1)
		              {
		                  led_index++;
		                  if (led_index >= 8) led_index = 0;
		                  LED_Update(led_index);
		              }
		              else if (lift_direction == 2)
		              {
		                  if (led_index == 0) led_index = 7;
		                  else led_index--;
		                  LED_Update(led_index);
		              }
		              else
		              {
		                  LED_Update(-1);
		              }
		          }

		          // 오디오 경고 장치 및 도어 제어
		          /* 하드웨어의 모든 부가 동작(소리, 문열림)을 논블로킹으로 동시 제어합니다. */
		          Buzzer_Update(lift_direction);
		          process_door_input(&elevator_door);
		          updateDoor(&elevator_door);
		      }

		      // ====================================================================
		      // 2. 비상 정지 상태 (CMD CLI 모드)
		      // ====================================================================
		      else if(state == STATE_EMERGENCY)
		      {
		    	  /* 관리자 명령어 입력을 받기 위해 UART 수신 인터럽트를 다시 켭니다. */
		    	  HAL_UART_Receive_IT(&huart2, &usart2_rxData, 1);
		          // [필수 방어코드] 하드웨어 즉시 셧다운 (모터 과열 방지)
		          if(EmergencyMsgflag == MSG_OFF)
		          {
		              motorStop();              // 승강기 모터 정지
		              LED_Update(-1);           // LED 모두 끄기
		              HAL_GPIO_WritePin(GPIOB, GPIO_PIN_2, GPIO_PIN_RESET); // 부저 끄기
		              lift_direction = 0;       // 방향 논리 초기화

		              printf("\r\nEMERGENCY!");
		              fflush(stdout);
		              EmergencyMsgflag = MSG_ON;
		          }

		          /* 상태에 맞춰 터미널 메시지가 단 1회만 출력되도록 플래그로 제어합니다. */
		          if(RecoverMsgflag == MSG_OFF){
		              printf("\r\nSYSTEM RECOVERING IN PROGRESS");
		              SysReset();
		              fflush(stdout);
		              RecoverMsgflag = MSG_ON;
		          }

		          if(TestRunMsgflag == MSG_OFF){
		              printf("\r\nTEST RUN");
		              printf("\r\nC:\\Admin> ");
		              fflush(stdout);
		              TestRunMsgflag = MSG_ON;
		          }

		          cmdExeTest(); // UART 명령어 처리
		      }

		      // ====================================================================
		      // 3. 복구 대기 상태
		      // ====================================================================
		      else if(state == STATE_IDLE)
		      {
		          cmdExeResume(); // 'y' / 'n' 대기
		      }

    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
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

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
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
// 비상 버튼 (PC9 핀)을 누르면 즉시 모든 동작을 멈추고 STATE_EMERGENCY로 진입
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    if(GPIO_Pin == GPIO_PIN_9)
    {
        if(state == STATE_NORMAL)
        {
        	/* 기존 통신 버퍼를 완전히 비워 쓰레기 값이 실행되는 것을 방지합니다. */
            queue_Flush();
            len = 0;
            cmd[0]= '\0';

            // 상태 변경
            state = STATE_EMERGENCY;

            // 플래그 초기화
            /* 메시지가 다시 정상적으로 출력될 수 있도록 출력 플래그를 원상 복구합니다. */
            EmergencyMsgflag = MSG_OFF;
            RecoverMsgflag = MSG_OFF;
            TestRunMsgflag = MSG_OFF;
        }
    }
}
/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
	/* User can add his own implementation to report the HAL error return state */
	__disable_irq();
	while (1)
	{
	}
  /* USER CODE END Error_Handler_Debug */
}
#ifdef USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  * where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
	/* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
