#include "fnd.h"

#include <stdint.h>

#define FND_DIGIT_COUNT 10U
#define FND_DP_MASK     0x80U

static const uint8_t legacyFont[FND_DIGIT_COUNT] = {
    0x3FU, 0x06U, 0x5BU, 0x4FU, 0x66U,
    0x6DU, 0x7DU, 0x27U, 0x7FU, 0x67U
};

static const uint8_t standardFont[FND_DIGIT_COUNT] = {
    0x3FU, 0x06U, 0x5BU, 0x4FU, 0x66U,
    0x6DU, 0x7DU, 0x07U, 0x7FU, 0x6FU
};

static uint8_t fndApplyPolarity(const Fnd *fnd, uint8_t pattern)
{
    return (fnd->polarity == FND_COMMON_ANODE)
               ? (uint8_t)~pattern
               : pattern;
}

static uint8_t fndGetDigitPattern(const Fnd *fnd, uint8_t digit)
{
    return (fnd->font == FND_FONT_STANDARD)
               ? standardFont[digit]
               : legacyFont[digit];
}

void fndInit(Fnd *fnd, volatile uint8_t *ddr, volatile uint8_t *port,
             FndPolarity polarity, FndFont font)
{
    fnd->ddr = ddr;
    fnd->port = port;
    fnd->polarity = polarity;
    fnd->font = font;

    // 1자리 FND가 Port 전체를 사용한다는 하드웨어 구성을 전제로 한다.
    *fnd->ddr = 0xFFU;
    fndClear(fnd);
}

void fndDisplayDigit(Fnd *fnd, uint8_t digit)
{
    if (digit >= FND_DIGIT_COUNT)
    {
        fndClear(fnd);
        return;
    }

    *fnd->port = fndApplyPolarity(fnd, fndGetDigitPattern(fnd, digit));
}

void fndDisplayDigitWithPoint(Fnd *fnd, uint8_t digit)
{
    if (digit >= FND_DIGIT_COUNT)
    {
        fndClear(fnd);
        return;
    }

    const uint8_t pattern =
        (uint8_t)(fndGetDigitPattern(fnd, digit) | FND_DP_MASK);
    *fnd->port = fndApplyPolarity(fnd, pattern);
}

void fndClear(Fnd *fnd)
{
    *fnd->port = fndApplyPolarity(fnd, 0x00U);
}
