#include "fnd4.h"

#include <avr/io.h>
#include <stdint.h>

#define FND4_DIGIT_MASK      0x0FU
#define FND4_COUNT_PERIOD_MS 100U
#define FND4_FRAMES_PER_COUNT \
    (FND4_COUNT_PERIOD_MS / FND4_FRAME_MS)

_Static_assert((FND4_COUNT_PERIOD_MS % FND4_FRAME_MS) == 0U,
               "Count period must be a multiple of one scan frame");

int main(void)
{
    Fnd4 fnd;
    uint16_t count = 0U;
    uint16_t scannedFrames = 0U;
    uint8_t digits[FND4_DIGIT_COUNT];

    /*
     * 예시 Mapping
     * PORTC[7:0] : DP,G,F,E,D,C,B,A Segment, Active-Low
     * PORTA[3:0] : 1000,100,10,1의 자리 선택, Active-Low
     */
    fnd4Init(&fnd,
             &DDRC, &PORTC,
             &DDRA, &PORTA,
             FND4_DIGIT_MASK,
             FND4_ACTIVE_LOW,
             FND4_ACTIVE_LOW);

    fnd4SplitNumber(count, digits);

    while (1)
    {
        // 1 ms × 4자리 = 약 4 ms마다 한 Display Frame을 갱신한다.
        fnd4ScanFrame(&fnd, digits);

        // Scan 속도와 Count 증가 속도를 별도의 Frame Counter로 분리한다.
        scannedFrames++;
        if (scannedFrames >= FND4_FRAMES_PER_COUNT)
        {
            scannedFrames = 0U;
            count++;

            if (count >= 10000U)
            {
                count = 0U;
            }

            fnd4SplitNumber(count, digits);
        }
    }
}
