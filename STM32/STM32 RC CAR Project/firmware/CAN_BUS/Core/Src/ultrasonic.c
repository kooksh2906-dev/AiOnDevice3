#include "ultrasonic.h"
#include "delay.h"
#include "tim.h"

#define MAX_VALID_CM 300U
#define HCSR04_SENSOR_NONE 0xFFU

static volatile uint16_t ic_value_rise[HCSR04_SENSOR_COUNT] = {0U, 0U, 0U};
static volatile uint16_t ic_value_fall[HCSR04_SENSOR_COUNT] = {0U, 0U, 0U};
static volatile uint16_t echo_time[HCSR04_SENSOR_COUNT] = {0U, 0U, 0U};
static volatile uint8_t capture_flag[HCSR04_SENSOR_COUNT] = {0U, 0U, 0U};
static volatile uint16_t distance_cm[HCSR04_SENSOR_COUNT] = {0U, 0U, 0U};
static volatile uint8_t measurement_ready[HCSR04_SENSOR_COUNT] = {0U, 0U, 0U};
static volatile uint8_t active_sensor = HCSR04_SENSOR_NONE;

static void HCSR04_TriggerSensor(HCSR04_Sensor_t sensor)
{
    GPIO_TypeDef *trigger_port;
    uint16_t trigger_pin;

    HAL_GPIO_WritePin(TRIG_F_GPIO_Port, TRIG_F_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(TRIG_L_GPIO_Port, TRIG_L_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(TRIG_R_GPIO_Port, TRIG_R_Pin, GPIO_PIN_RESET);
    delay_us(2U);

    switch (sensor) {
    case HCSR04_SENSOR_FRONT:
        trigger_port = TRIG_F_GPIO_Port;
        trigger_pin = TRIG_F_Pin;
        break;

    case HCSR04_SENSOR_LEFT:
        trigger_port = TRIG_L_GPIO_Port;
        trigger_pin = TRIG_L_Pin;
        break;

    case HCSR04_SENSOR_RIGHT:
        trigger_port = TRIG_R_GPIO_Port;
        trigger_pin = TRIG_R_Pin;
        break;

    default:
        return;
    }

    HAL_GPIO_WritePin(trigger_port, trigger_pin, GPIO_PIN_SET);
    delay_us(10U);
    HAL_GPIO_WritePin(trigger_port, trigger_pin, GPIO_PIN_RESET);
}

void HCSR04_BeginMeasurement(HCSR04_Sensor_t sensor)
{
    uint8_t index;
    uint32_t channel;
    uint32_t channel_flag;

    switch (sensor) {
    case HCSR04_SENSOR_FRONT:
        index = (uint8_t)HCSR04_SENSOR_FRONT;
        channel = TIM_CHANNEL_1;
        channel_flag = TIM_FLAG_CC1;
        break;

    case HCSR04_SENSOR_LEFT:
        index = (uint8_t)HCSR04_SENSOR_LEFT;
        channel = TIM_CHANNEL_2;
        channel_flag = TIM_FLAG_CC2;
        break;

    case HCSR04_SENSOR_RIGHT:
        index = (uint8_t)HCSR04_SENSOR_RIGHT;
        channel = TIM_CHANNEL_3;
        channel_flag = TIM_FLAG_CC3;
        break;

    default:
        return;
    }

    HAL_NVIC_DisableIRQ(TIM4_IRQn);

    capture_flag[index] = 0U;
    measurement_ready[index] = 0U;
    __HAL_TIM_SET_CAPTUREPOLARITY(&htim4, channel, TIM_INPUTCHANNELPOLARITY_RISING);
    __HAL_TIM_CLEAR_FLAG(&htim4, channel_flag);
    __HAL_TIM_SET_COUNTER(&htim4, 0U);
    active_sensor = index;

    HAL_NVIC_ClearPendingIRQ(TIM4_IRQn);
    HAL_NVIC_EnableIRQ(TIM4_IRQn);
    HCSR04_TriggerSensor(sensor);
}

void HCSR04_ReadSnapshot(uint16_t measured_distance[3], uint8_t valid[3])
{
    HAL_NVIC_DisableIRQ(TIM4_IRQn);
    for (uint8_t i = 0U; i < (uint8_t)HCSR04_SENSOR_COUNT; ++i) {
        measured_distance[i] = distance_cm[i];
        valid[i] = measurement_ready[i];
    }
    HAL_NVIC_EnableIRQ(TIM4_IRQn);
}

static void HCSR04_ProcessChannel(TIM_HandleTypeDef *htim,
                                  uint8_t index,
                                  uint32_t channel)
{
    if (capture_flag[index] == 0U) {
        ic_value_rise[index] = (uint16_t)HAL_TIM_ReadCapturedValue(htim, channel);
        capture_flag[index] = 1U;
        __HAL_TIM_SET_CAPTUREPOLARITY(htim, channel, TIM_INPUTCHANNELPOLARITY_FALLING);
    } else {
        ic_value_fall[index] = (uint16_t)HAL_TIM_ReadCapturedValue(htim, channel);

        if (ic_value_fall[index] >= ic_value_rise[index]) {
            echo_time[index] = ic_value_fall[index] - ic_value_rise[index];
        } else {
            echo_time[index] =
                (uint16_t)((0x10000UL - ic_value_rise[index]) + ic_value_fall[index]);
        }

        distance_cm[index] = (echo_time[index] / 58U > MAX_VALID_CM)
                           ? MAX_VALID_CM
                           : (uint16_t)(echo_time[index] / 58U);
        measurement_ready[index] = (distance_cm[index] > 0U) ? 1U : 0U;

        capture_flag[index] = 0U;
        __HAL_TIM_SET_CAPTUREPOLARITY(htim, channel, TIM_INPUTCHANNELPOLARITY_RISING);
        active_sensor = HCSR04_SENSOR_NONE;
    }
}

void HAL_TIM_IC_CaptureCallback(TIM_HandleTypeDef *htim)
{
    if (htim->Instance != TIM4) {
        return;
    }

    if ((active_sensor == HCSR04_SENSOR_FRONT) &&
        (htim->Channel == HAL_TIM_ACTIVE_CHANNEL_1)) {
        HCSR04_ProcessChannel(htim, (uint8_t)HCSR04_SENSOR_FRONT, TIM_CHANNEL_1);
    }

    if ((active_sensor == HCSR04_SENSOR_LEFT) &&
        (htim->Channel == HAL_TIM_ACTIVE_CHANNEL_2)) {
        HCSR04_ProcessChannel(htim, (uint8_t)HCSR04_SENSOR_LEFT, TIM_CHANNEL_2);
    }

    if ((active_sensor == HCSR04_SENSOR_RIGHT) &&
        (htim->Channel == HAL_TIM_ACTIVE_CHANNEL_3)) {
        HCSR04_ProcessChannel(htim, (uint8_t)HCSR04_SENSOR_RIGHT, TIM_CHANNEL_3);
    }
}
