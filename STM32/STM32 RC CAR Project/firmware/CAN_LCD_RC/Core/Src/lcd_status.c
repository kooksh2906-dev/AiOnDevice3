#include "lcd_status.h"

#include "can_app.h"
#include "cmsis_os2.h"
#include "lcd_i2c.h"
#include "main.h"

#include <stdio.h>

static const char *DirectionText(CanDirection_t direction);

void LcdStatus_Task(void *argument)
{
    (void)argument;

    /*
     * 전원 인가 직후 LCD 안정화 시간
     */
    osDelay(100);

    /*
     * I2C LCD 초기화
     */
    i2c_lcd_init();
    lcd_clear();
    lcd_show_ready();

    osDelay(1000);
    /* Infinite loop */
    for(;;)
    {
        CanVehicleStatus_t status;
        char line1[17];
        char line2[17];

        if (CAN_App_GetLatestStatus(&status) != 0U) {
            uint32_t last_tick = CAN_App_GetLastRxTick();
            uint32_t now = HAL_GetTick();

            if ((now - last_tick) > 1000U) {
                lcd_print_line(0, "CAN SPEED CTRL");
                lcd_print_line(1, "CAN TIMEOUT");
            } else {
                snprintf(line1, sizeof(line1),
                         "SPD:%3u%% F:%3u",
                         status.speed_percent,
                         status.front_distance);

                snprintf(line2, sizeof(line2),
                         "DIR:%-5s A:%3u",
                         DirectionText(status.direction),
                         status.alive_count);

                lcd_print_line(0, line1);
                lcd_print_line(1, line2);
            }
        } else {
            lcd_show_waiting_can();
        }

        osDelay(200);
    }
}

static const char *DirectionText(CanDirection_t direction)
{
    switch (direction) {
    case CAN_DIR_STOP:
        return "STOP";
    case CAN_DIR_FORWARD:
        return "FWD";
    case CAN_DIR_LEFT:
        return "LEFT";
    case CAN_DIR_RIGHT:
        return "RIGHT";
    case CAN_DIR_BACK:
        return "BACK";
    case CAN_DIR_AVOID:
        return "AVOID";
    default:
        return "UNK";
    }
}
