#include <stdint.h>

#define RCC_CR_HSEON                (1 << 16)       // HSE 오실레이터 비트 -> ON
#define RCC_CR_HSERDY               (1 << 17)       // HSE Ready 플래그
#define RCC_CR_PLLON                (1 << 24)       // PLL 오실레이터 비트 -> ON
#define RCC_CR_PLLRDY               (1 << 25)       // PLL Ready 플래그

#define RCC_PLLCFGR_PLLM_Pos        0               // PLLM 위치
#define RCC_PLLCFGR_PLLN_Pos        6               // PLLN 위치
#define RCC_PLLCFGR_PLLP_Pos        16              // PLLP 위치
#define RCC_PLLCFGR_PLLSRC_Pos      22              // PLLSRC 위치

#define FLASH_ACR_LATENCY_Pos       0
#define FLASH_ACR_LATENCY_3Ws       (3 << FLASH_ACR_LATENCY_Pos)    // 3 Wait state 설정

#define RCC_CFGR_SW_Pos             0               // 시스템 클럭 소스 선택 스위치
#define RCC_CFGR_SW_PLL             (2 << RCC_CFGR_SW_Pos)          // PLL 선택
#define RCC_CFGR_HPRE_Pos           4               // AHB 프리스케일러 위치
#define RCC_CFGR_PPRE1_Pos          10              // APB1 프리스케일러 위치
#define RCC_CFGR_PPRE2_Pos          13              // APB2 프리스케일러 위치

#define RCC_AHB1ENR_GPIOAEN         (1 << 0)        // GPIOA 클럭 인에이블
#define GPIOA_MODER_MODER5          (1 << (5 * 2))  // PA5번 출력 모드 설정
#define GPIOA_ODR_ODR5              (1 << 5)        // PA5번의 출력 데이터 비트

#define RCC_BASE                    0x40023800      // RCC Base Address
#define FLASH_BASE                  0x40023C00
#define GPIOA_BASE                  0x40020000

#define RCC_CR                      (*(volatile uint32_t *)(RCC_BASE + 0x00))
#define RCC_PLLCFGR                 (*(volatile uint32_t *)(RCC_BASE + 0x04))
#define RCC_CFGR                    (*(volatile uint32_t *)(RCC_BASE + 0x08))
#define FLASH_ACR                   (*(volatile uint32_t *)(FLASH_BASE + 0x00))
#define GPIOA_MODER                 (*(volatile uint32_t *)(GPIOA_BASE + 0x00))
#define GPIOA_ODR                   (*(volatile uint32_t *)(GPIOA_BASE + 0x14))
#define RCC_AHB1ENR                 (*(volatile uint32_t *)(RCC_BASE + 0x30))


void SystemClock_Config(void)
{
    // 1. HSE 활성화
    RCC_CR |= RCC_CR_HSEON;                 // HSE On
    while(!(RCC_CR & RCC_CR_HSERDY));       // HSE Ready 대기

    // 2. PLLM, PLLN, PLLP 설정
    // HSE 8MHz -> 100MHz
    RCC_PLLCFGR = (4 << RCC_PLLCFGR_PLLM_Pos) |
                  (200 << RCC_PLLCFGR_PLLN_Pos) |
                  (0x01 << RCC_PLLCFGR_PLLP_Pos) |
                  (1 << RCC_PLLCFGR_PLLSRC_Pos);

    // 3. PLL 활성화
    RCC_CR |= RCC_CR_PLLON;                 // PLL On
    while(!(RCC_CR & RCC_CR_PLLRDY));       // PLL Flag 대기

    // 4. AHB, APB1, APB2 분주기 설정
    RCC_CFGR |= (0 << RCC_CFGR_HPRE_Pos);       // 100MHz
    RCC_CFGR |= (4 << RCC_CFGR_PPRE1_Pos);      // 50MHz
    RCC_CFGR |= (0 << RCC_CFGR_PPRE2_Pos);      // 100MHz

    // 5. 플래시 메모리 설정
    FLASH_ACR |= FLASH_ACR_LATENCY_3Ws;

    // 6. 시스템 클럭 소스 PLL 선택
    RCC_CFGR |= RCC_CFGR_SW_PLL;
    while((RCC_CFGR & RCC_CFGR_SW_PLL) != RCC_CFGR_SW_PLL);
}




int main(void)
{
    SystemClock_Config();

    RCC_AHB1ENR |= RCC_AHB1ENR_GPIOAEN; // GPIOA 클럭 활성화
    GPIOA_MODER |= GPIOA_MODER_MODER5;  // 출력 모드 설정

    while(1)
    {
        GPIOA_ODR ^= GPIOA_ODR_ODR5;        // 토글
        for(volatile int i = 0; i < 10000000; i++);
    }
}
