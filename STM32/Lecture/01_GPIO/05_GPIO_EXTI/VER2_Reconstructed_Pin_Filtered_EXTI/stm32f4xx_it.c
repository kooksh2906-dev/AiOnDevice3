#include "main.h"

void EXTI15_10_IRQHandler(void)
{
    /* HAL Handler가 EXTI13 Pending을 확인·해제한 뒤 Callback을 호출합니다. */
    HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_13);
}
