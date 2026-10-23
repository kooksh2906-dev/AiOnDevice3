#include <stdint.h>

/* Base addresses */
#define RCC_BASE                    0x40023800UL
#define FLASH_BASE                  0x40023C00UL
#define GPIOA_BASE                  0x40020000UL
#define SYSTICK_BASE                0xE000E010UL

/* RCC registers */
#define RCC_CR                      (*(volatile uint32_t *)(RCC_BASE + 0x00UL))
#define RCC_PLLCFGR                 (*(volatile uint32_t *)(RCC_BASE + 0x04UL))
#define RCC_CFGR                    (*(volatile uint32_t *)(RCC_BASE + 0x08UL))
#define RCC_AHB1ENR                 (*(volatile uint32_t *)(RCC_BASE + 0x30UL))

/* FLASH registers */
#define FLASH_ACR                   (*(volatile uint32_t *)(FLASH_BASE + 0x00UL))

/* GPIOA registers */
#define GPIOA_MODER                 (*(volatile uint32_t *)(GPIOA_BASE + 0x00UL))
#define GPIOA_OTYPER                (*(volatile uint32_t *)(GPIOA_BASE + 0x04UL))
#define GPIOA_OSPEEDR               (*(volatile uint32_t *)(GPIOA_BASE + 0x08UL))
#define GPIOA_PUPDR                 (*(volatile uint32_t *)(GPIOA_BASE + 0x0CUL))
#define GPIOA_ODR                   (*(volatile uint32_t *)(GPIOA_BASE + 0x14UL))

/* SysTick registers */
#define SYSTICK_CTRL                (*(volatile uint32_t *)(SYSTICK_BASE + 0x00UL))
#define SYSTICK_LOAD                (*(volatile uint32_t *)(SYSTICK_BASE + 0x04UL))
#define SYSTICK_VAL                 (*(volatile uint32_t *)(SYSTICK_BASE + 0x08UL))

/* RCC_CR */
#define RCC_CR_HSEON                (1UL << 16)
#define RCC_CR_HSERDY               (1UL << 17)
#define RCC_CR_HSEBYP               (1UL << 18)
#define RCC_CR_PLLON                (1UL << 24)
#define RCC_CR_PLLRDY               (1UL << 25)

/* RCC_PLLCFGR */
#define RCC_PLLCFGR_PLLM_Pos        0U
#define RCC_PLLCFGR_PLLM_Msk        (0x3FUL << RCC_PLLCFGR_PLLM_Pos)
#define RCC_PLLCFGR_PLLN_Pos        6U
#define RCC_PLLCFGR_PLLN_Msk        (0x1FFUL << RCC_PLLCFGR_PLLN_Pos)
#define RCC_PLLCFGR_PLLP_Pos        16U
#define RCC_PLLCFGR_PLLP_Msk        (0x3UL << RCC_PLLCFGR_PLLP_Pos)
#define RCC_PLLCFGR_PLLSRC_HSE      (1UL << 22)
#define RCC_PLLCFGR_PLLQ_Pos        24U
#define RCC_PLLCFGR_PLLQ_Msk        (0xFUL << RCC_PLLCFGR_PLLQ_Pos)

/* RCC_CFGR */
#define RCC_CFGR_SW_Msk             (0x3UL << 0U)
#define RCC_CFGR_SW_PLL             (0x2UL << 0U)
#define RCC_CFGR_SWS_Msk            (0x3UL << 2U)
#define RCC_CFGR_SWS_PLL            (0x2UL << 2U)
#define RCC_CFGR_HPRE_Msk           (0xFUL << 4U)
#define RCC_CFGR_PPRE1_Msk          (0x7UL << 10U)
#define RCC_CFGR_PPRE1_DIV2         (0x4UL << 10U)
#define RCC_CFGR_PPRE2_Msk          (0x7UL << 13U)

/* FLASH_ACR */
#define FLASH_ACR_LATENCY_Msk       (0xFUL << 0U)
#define FLASH_ACR_LATENCY_3WS       (0x3UL << 0U)
#define FLASH_ACR_PRFTEN            (1UL << 8U)
#define FLASH_ACR_ICEN              (1UL << 9U)
#define FLASH_ACR_DCEN              (1UL << 10U)

/* GPIOA */
#define RCC_AHB1ENR_GPIOAEN         (1UL << 0U)
#define GPIO_PIN_5                  (1UL << 5U)
#define GPIO_MODER5_Msk             (0x3UL << (5U * 2U))
#define GPIO_MODER5_OUTPUT          (0x1UL << (5U * 2U))
#define GPIO_OT5                    (1UL << 5U)
#define GPIO_OSPEEDR5_Msk           (0x3UL << (5U * 2U))
#define GPIO_PUPDR5_Msk             (0x3UL << (5U * 2U))

/* SysTick CTRL */
#define SYSTICK_CTRL_ENABLE         (1UL << 0U)
#define SYSTICK_CTRL_CLKSOURCE      (1UL << 2U)
#define SYSTICK_CTRL_COUNTFLAG      (1UL << 16U)

#define SYSTEM_CORE_CLOCK_HZ        100000000UL
#define SYSTICK_TICKS_PER_MS        (SYSTEM_CORE_CLOCK_HZ / 1000UL)

static void SystemClock_Config(void);
static void GPIOA_LED_Init(void);
static void SysTick_Init(void);
static void delay_ms(uint32_t ms);

int main(void)
{
    SystemClock_Config();
    GPIOA_LED_Init();
    SysTick_Init();

    while (1)
    {
        /* 단일 실행 흐름에서 PA5의 현재 출력 상태를 반전합니다. */
        GPIOA_ODR ^= GPIO_PIN_5;
        delay_ms(1000U);
    }
}

static void SystemClock_Config(void)
{
    uint32_t pll_config;
    uint32_t bus_config;

    /*
     * NUCLEO-F411RE 기본 구성은 ST-LINK MCO의 8 MHz 디지털 클럭을
     * PH0/OSC_IN으로 공급하므로 HSE Bypass를 HSEON보다 먼저 설정합니다.
     */
    RCC_CR |= RCC_CR_HSEBYP;
    RCC_CR |= RCC_CR_HSEON;
    while ((RCC_CR & RCC_CR_HSERDY) == 0U)
    {
        /* HSE 안정화 대기 */
    }

    /*
     * HSE 8 MHz / PLLM 4 = 2 MHz
     * 2 MHz * PLLN 200 = VCO 400 MHz
     * 400 MHz / PLLP 4 = SYSCLK 100 MHz
     * PLLQ 8은 PLLQ 필드를 유효 범위로 설정하며 48 MHz 계열 주변장치는 사용하지 않습니다.
     */
    pll_config = RCC_PLLCFGR;
    pll_config &= ~(RCC_PLLCFGR_PLLM_Msk |
                    RCC_PLLCFGR_PLLN_Msk |
                    RCC_PLLCFGR_PLLP_Msk |
                    RCC_PLLCFGR_PLLSRC_HSE |
                    RCC_PLLCFGR_PLLQ_Msk);
    pll_config |= (4UL << RCC_PLLCFGR_PLLM_Pos) |
                  (200UL << RCC_PLLCFGR_PLLN_Pos) |
                  (0x1UL << RCC_PLLCFGR_PLLP_Pos) |
                  RCC_PLLCFGR_PLLSRC_HSE |
                  (8UL << RCC_PLLCFGR_PLLQ_Pos);
    RCC_PLLCFGR = pll_config;

    /* 3.3 V 보드에서 100 MHz Flash 접근을 위한 3 Wait State와 ART 기능 설정 */
    FLASH_ACR = (FLASH_ACR & ~FLASH_ACR_LATENCY_Msk) |
                FLASH_ACR_LATENCY_3WS |
                FLASH_ACR_PRFTEN |
                FLASH_ACR_ICEN |
                FLASH_ACR_DCEN;

    /* AHB = 100 MHz, APB1 = 50 MHz, APB2 = 100 MHz */
    bus_config = RCC_CFGR;
    bus_config &= ~(RCC_CFGR_HPRE_Msk |
                    RCC_CFGR_PPRE1_Msk |
                    RCC_CFGR_PPRE2_Msk);
    bus_config |= RCC_CFGR_PPRE1_DIV2;
    RCC_CFGR = bus_config;

    RCC_CR |= RCC_CR_PLLON;
    while ((RCC_CR & RCC_CR_PLLRDY) == 0U)
    {
        /* PLL 안정화 대기 */
    }

    RCC_CFGR = (RCC_CFGR & ~RCC_CFGR_SW_Msk) | RCC_CFGR_SW_PLL;

    /* SW는 요청 필드이고 SWS는 실제 적용 상태이므로 SWS[1:0]을 확인합니다. */
    while ((RCC_CFGR & RCC_CFGR_SWS_Msk) != RCC_CFGR_SWS_PLL)
    {
        /* PLL이 System Clock으로 적용될 때까지 대기 */
    }
}

static void GPIOA_LED_Init(void)
{
    RCC_AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    (void)RCC_AHB1ENR;

    /* PA5: General-purpose output, Push-Pull, Low speed, No pull */
    GPIOA_MODER = (GPIOA_MODER & ~GPIO_MODER5_Msk) | GPIO_MODER5_OUTPUT;
    GPIOA_OTYPER &= ~GPIO_OT5;
    GPIOA_OSPEEDR &= ~GPIO_OSPEEDR5_Msk;
    GPIOA_PUPDR &= ~GPIO_PUPDR5_Msk;
}

static void SysTick_Init(void)
{
    /* Processor Clock 100 MHz를 100,000회 계수하여 1 ms 주기를 만듭니다. */
    SYSTICK_LOAD = SYSTICK_TICKS_PER_MS - 1UL;
    SYSTICK_VAL = 0UL;
    SYSTICK_CTRL = SYSTICK_CTRL_CLKSOURCE | SYSTICK_CTRL_ENABLE;
}

static void delay_ms(uint32_t ms)
{
    for (uint32_t elapsed_ms = 0U; elapsed_ms < ms; elapsed_ms++)
    {
        while ((SYSTICK_CTRL & SYSTICK_CTRL_COUNTFLAG) == 0U)
        {
            /* COUNTFLAG Polling: 대기 중 다른 작업을 수행하지 않는 Blocking 방식 */
        }
    }
}
