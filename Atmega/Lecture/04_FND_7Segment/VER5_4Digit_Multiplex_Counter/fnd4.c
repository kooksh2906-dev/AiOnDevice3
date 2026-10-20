#include "fnd4.h"

#include <util/delay.h>

#define FND4_VALUE_LIMIT 10000U

// FPGA SoC 예제와 같은 표준 7·9 글꼴을 사용한다.
static const uint8_t standardFont[10] = {
    0x3FU, 0x06U, 0x5BU, 0x4FU, 0x66U,
    0x6DU, 0x7DU, 0x07U, 0x7FU, 0x6FU
};

static uint8_t fnd4ApplyPolarity(uint8_t pattern, Fnd4Polarity polarity)
{
    return (polarity == FND4_ACTIVE_LOW) ? (uint8_t)~pattern : pattern;
}

static void fnd4WriteDigitBits(Fnd4 *fnd, uint8_t digitBits)
{
    const uint8_t preservedBits = (uint8_t)(*fnd->digitPort &
                                             (uint8_t)~fnd->digitMask);
    *fnd->digitPort = (uint8_t)(preservedBits |
                                (digitBits & fnd->digitMask));
}

static void fnd4DisableAllDigits(Fnd4 *fnd)
{
    const uint8_t offBits = (fnd->digitPolarity == FND4_ACTIVE_LOW)
                                ? fnd->digitMask
                                : 0x00U;
    fnd4WriteDigitBits(fnd, offBits);
}

static void fnd4EnableDigit(Fnd4 *fnd, uint8_t digitIndex)
{
    const uint8_t selectedBit = (uint8_t)(1U << digitIndex);
    const uint8_t digitBits = (fnd->digitPolarity == FND4_ACTIVE_LOW)
                                  ? (uint8_t)(fnd->digitMask &
                                              (uint8_t)~selectedBit)
                                  : selectedBit;
    fnd4WriteDigitBits(fnd, digitBits);
}

void fnd4Init(Fnd4 *fnd,
              volatile uint8_t *segmentDdr,
              volatile uint8_t *segmentPort,
              volatile uint8_t *digitDdr,
              volatile uint8_t *digitPort,
              uint8_t digitMask,
              Fnd4Polarity segmentPolarity,
              Fnd4Polarity digitPolarity)
{
    fnd->segmentDdr = segmentDdr;
    fnd->segmentPort = segmentPort;
    fnd->digitDdr = digitDdr;
    fnd->digitPort = digitPort;
    fnd->digitMask = digitMask;
    fnd->segmentPolarity = segmentPolarity;
    fnd->digitPolarity = digitPolarity;

    *fnd->segmentDdr = 0xFFU;
    *fnd->digitDdr |= fnd->digitMask;
    fnd4Clear(fnd);
}

void fnd4SplitNumber(uint16_t number, uint8_t digits[FND4_DIGIT_COUNT])
{
    number %= FND4_VALUE_LIMIT;

    // Index 0부터 1·10·100·1000의 자리 순서로 저장한다.
    digits[0] = (uint8_t)(number % 10U);
    digits[1] = (uint8_t)((number / 10U) % 10U);
    digits[2] = (uint8_t)((number / 100U) % 10U);
    digits[3] = (uint8_t)((number / 1000U) % 10U);
}

void fnd4ScanFrame(Fnd4 *fnd, const uint8_t digits[FND4_DIGIT_COUNT])
{
    for (uint8_t digitIndex = 0U;
         digitIndex < FND4_DIGIT_COUNT;
         digitIndex++)
    {
        /*
         * 이전 자리의 Common 신호를 먼저 끈 뒤 Segment를 바꿔
         * 새 Pattern이 이전 자리에 순간적으로 보이는 Ghosting을 줄인다.
         */
        fnd4DisableAllDigits(fnd);

        const uint8_t segmentPattern = standardFont[digits[digitIndex]];
        *fnd->segmentPort =
            fnd4ApplyPolarity(segmentPattern, fnd->segmentPolarity);

        fnd4EnableDigit(fnd, digitIndex);
        _delay_ms(FND4_SCAN_SLOT_MS);
        fnd4DisableAllDigits(fnd);
    }
}

void fnd4Clear(Fnd4 *fnd)
{
    fnd4DisableAllDigits(fnd);
    *fnd->segmentPort =
        fnd4ApplyPolarity(0x00U, fnd->segmentPolarity);
}
