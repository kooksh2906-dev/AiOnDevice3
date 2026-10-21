/* USER CODE BEGIN PV */
uint8_t data = 0;
/* USER CODE END PV */

/* USER CODE BEGIN WHILE */
while (1)
{
    data = HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_4);
    HAL_Delay(200);

    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
}
/* USER CODE END 3 */

