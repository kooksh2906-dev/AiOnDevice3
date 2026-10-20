#ifndef FND4_H_
#define FND4_H_

#include <stdint.h>

#define FND4_DIGIT_COUNT  4U
#define FND4_SCAN_SLOT_MS 1U
#define FND4_FRAME_MS     (FND4_DIGIT_COUNT * FND4_SCAN_SLOT_MS)

typedef enum
{
    FND4_ACTIVE_HIGH = 0,
    FND4_ACTIVE_LOW
} Fnd4Polarity;

typedef struct
{
    volatile uint8_t *segmentDdr;
    volatile uint8_t *segmentPort;
    volatile uint8_t *digitDdr;
    volatile uint8_t *digitPort;
    uint8_t digitMask;
    Fnd4Polarity segmentPolarity;
    Fnd4Polarity digitPolarity;
} Fnd4;

void fnd4Init(Fnd4 *fnd,
              volatile uint8_t *segmentDdr,
              volatile uint8_t *segmentPort,
              volatile uint8_t *digitDdr,
              volatile uint8_t *digitPort,
              uint8_t digitMask,
              Fnd4Polarity segmentPolarity,
              Fnd4Polarity digitPolarity);
void fnd4SplitNumber(uint16_t number, uint8_t digits[FND4_DIGIT_COUNT]);
void fnd4ScanFrame(Fnd4 *fnd, const uint8_t digits[FND4_DIGIT_COUNT]);
void fnd4Clear(Fnd4 *fnd);

#endif /* FND4_H_ */
