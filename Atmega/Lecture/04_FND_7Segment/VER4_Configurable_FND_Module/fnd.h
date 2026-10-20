#ifndef FND_H_
#define FND_H_

#include <stdint.h>

typedef enum
{
    FND_COMMON_CATHODE = 0,
    FND_COMMON_ANODE
} FndPolarity;

typedef enum
{
    FND_FONT_LEGACY = 0,
    FND_FONT_STANDARD
} FndFont;

typedef struct
{
    volatile uint8_t *ddr;
    volatile uint8_t *port;
    FndPolarity polarity;
    FndFont font;
} Fnd;

void fndInit(Fnd *fnd, volatile uint8_t *ddr, volatile uint8_t *port,
             FndPolarity polarity, FndFont font);
void fndDisplayDigit(Fnd *fnd, uint8_t digit);
void fndDisplayDigitWithPoint(Fnd *fnd, uint8_t digit);
void fndClear(Fnd *fnd);

#endif /* FND_H_ */
