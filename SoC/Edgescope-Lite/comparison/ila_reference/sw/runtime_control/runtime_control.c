/*
 * EdgeScope-Lite ILA reference: Step 6 runtime-control firmware.
 *
 * UART protocol (ASCII, one command per CR/LF-terminated line):
 *   PING
 *   STATUS
 *   CLEAR
 *   RUN <id>
 *   RUN <id> <pulse_width_cycles>
 *   HELP
 *
 * Test IDs 1..6 and the AXI GPIO control/status map are frozen by the common
 * deterministic test-pattern-generator contract.  Replies always start with
 * "OK" or "ERR" so a host script can parse them without terminal-specific
 * formatting.
 */

typedef unsigned char      uint8_t;
typedef unsigned int       uint32_t;
typedef unsigned long      uintptr_t;

#define AXI_GPIO_BASE             ((uintptr_t)0x40000000u)
#define GPIO_DATA_OFFSET          0x00u
#define GPIO_TRI_OFFSET           0x04u
#define GPIO_DATA2_OFFSET         0x08u
#define GPIO_TRI2_OFFSET          0x0Cu

#define AXI_UARTLITE_BASE         ((uintptr_t)0x40600000u)
#define UART_RX_FIFO_OFFSET       0x00u
#define UART_TX_FIFO_OFFSET       0x04u
#define UART_STATUS_OFFSET        0x08u
#define UART_CONTROL_OFFSET       0x0Cu

#define UART_STATUS_RX_VALID      (1u << 0)
#define UART_STATUS_TX_FULL       (1u << 3)
#define UART_CONTROL_RESET_TX     (1u << 0)
#define UART_CONTROL_RESET_RX     (1u << 1)

#define CONTROL_START_LEVEL       (1u << 0)
#define CONTROL_TEST_ID_SHIFT     1u
#define CONTROL_TEST_ID_MASK      (0xFu << CONTROL_TEST_ID_SHIFT)
#define CONTROL_PULSE_SHIFT       5u
#define CONTROL_PULSE_MASK        (0xFFFFFu << CONTROL_PULSE_SHIFT)
#define CONTROL_CLEAR             (1u << 25)

#define STATUS_BUSY               (1u << 0)
#define STATUS_DONE               (1u << 1)

#define TEST_ID_MIN               1u
#define TEST_ID_MAX               6u
#define DEFAULT_PULSE_WIDTH       10u
#define MAX_PULSE_WIDTH           0xFFFFFu

/*
 * This is a bounded count of AXI GPIO status reads, not a calibrated timer.
 * It comfortably covers the longest frozen generator case (100 ms) while
 * ensuring a disconnected or damaged generator cannot block forever.
 */
#define RUN_TIMEOUT_POLLS         50000000u
#define CLEAR_TIMEOUT_POLLS       100000u
#define UART_TX_TIMEOUT_POLLS     10000000u
#define COMMAND_BUFFER_SIZE       64u

static uint32_t last_control;

static inline void io_fence(void)
{
    __asm__ volatile ("fence iorw, iorw" : : : "memory");
}

static inline void mmio_write32(uintptr_t address, uint32_t value)
{
    *(volatile uint32_t *)address = value;
    io_fence();
}

static inline uint32_t mmio_read32(uintptr_t address)
{
    uint32_t value;

    io_fence();
    value = *(volatile uint32_t *)address;
    io_fence();
    return value;
}

static uint32_t gpio_status(void)
{
    return mmio_read32(AXI_GPIO_BASE + GPIO_DATA2_OFFSET) &
           (STATUS_BUSY | STATUS_DONE);
}

static int uart_putc(char character)
{
    uint32_t count;

    for (count = 0u; count < UART_TX_TIMEOUT_POLLS; ++count) {
        if ((mmio_read32(AXI_UARTLITE_BASE + UART_STATUS_OFFSET) &
             UART_STATUS_TX_FULL) == 0u) {
            mmio_write32(AXI_UARTLITE_BASE + UART_TX_FIFO_OFFSET,
                         (uint32_t)(uint8_t)character);
            return 1;
        }
    }
    return 0;
}

static void uart_puts(const char *text)
{
    while (*text != '\0') {
        if (!uart_putc(*text)) {
            return;
        }
        ++text;
    }
}

static void uart_put_hex32(uint32_t value)
{
    static const char digits[] = "0123456789ABCDEF";
    uint32_t shift;

    uart_puts("0x");
    shift = 28u;
    for (;;) {
        uart_putc(digits[(value >> shift) & 0xFu]);
        if (shift == 0u) {
            break;
        }
        shift -= 4u;
    }
}

static char uart_getc_blocking(void)
{
    for (;;) {
        if ((mmio_read32(AXI_UARTLITE_BASE + UART_STATUS_OFFSET) &
             UART_STATUS_RX_VALID) != 0u) {
            return (char)(uint8_t)mmio_read32(AXI_UARTLITE_BASE +
                                             UART_RX_FIFO_OFFSET);
        }
    }
}

static char ascii_upper(char character)
{
    if ((character >= 'a') && (character <= 'z')) {
        return (char)(character - ('a' - 'A'));
    }
    return character;
}

static char *skip_spaces(char *cursor)
{
    while ((*cursor == ' ') || (*cursor == '\t')) {
        ++cursor;
    }
    return cursor;
}

static int token_equals(const char *token, const char *expected)
{
    while ((*token != '\0') && (*expected != '\0')) {
        if (ascii_upper(*token) != *expected) {
            return 0;
        }
        ++token;
        ++expected;
    }
    return (*token == '\0') && (*expected == '\0');
}

static int parse_u32(char **cursor_io, uint32_t *value_out)
{
    char *cursor = skip_spaces(*cursor_io);
    uint32_t base = 10u;
    uint32_t value = 0u;
    uint32_t digits = 0u;

    if ((cursor[0] == '0') &&
        ((cursor[1] == 'x') || (cursor[1] == 'X'))) {
        base = 16u;
        cursor += 2;
    }

    for (;;) {
        uint32_t digit;
        char character = *cursor;

        if ((character >= '0') && (character <= '9')) {
            digit = (uint32_t)(character - '0');
        } else if ((ascii_upper(character) >= 'A') &&
                   (ascii_upper(character) <= 'F')) {
            digit = (uint32_t)(ascii_upper(character) - 'A') + 10u;
        } else {
            break;
        }

        if (digit >= base) {
            break;
        }

        if (base == 16u) {
            if (value > 0x0FFFFFFFu) {
                return 0;
            }
            value = (value << 4) | digit;
        } else {
            if ((value > 429496729u) ||
                ((value == 429496729u) && (digit > 5u))) {
                return 0;
            }
            value = (value << 3) + (value << 1) + digit;
        }

        ++digits;
        ++cursor;
    }

    if (digits == 0u) {
        return 0;
    }

    *cursor_io = cursor;
    *value_out = value;
    return 1;
}

static int only_spaces_remain(char *cursor)
{
    return *skip_spaces(cursor) == '\0';
}

static void reply_status(const char *prefix)
{
    uint32_t status = gpio_status();

    uart_puts(prefix);
    uart_puts(" status=");
    uart_put_hex32(status);
    uart_puts(" busy=");
    uart_putc((status & STATUS_BUSY) != 0u ? '1' : '0');
    uart_puts(" done=");
    uart_putc((status & STATUS_DONE) != 0u ? '1' : '0');
    uart_puts(" control=");
    uart_put_hex32(last_control);
    uart_puts("\r\n");
}

static int clear_generator(void)
{
    uint32_t count;

    mmio_write32(AXI_GPIO_BASE + GPIO_DATA_OFFSET, CONTROL_CLEAR);
    mmio_write32(AXI_GPIO_BASE + GPIO_DATA_OFFSET, 0u);
    last_control = 0u;

    for (count = 0u; count < CLEAR_TIMEOUT_POLLS; ++count) {
        if (gpio_status() == 0u) {
            return 1;
        }
    }
    return 0;
}

static void command_clear(void)
{
    if (clear_generator()) {
        reply_status("OK CLEAR");
    } else {
        reply_status("ERR CLEAR code=TIMEOUT");
    }
}

static void command_run(char *arguments)
{
    uint32_t test_id;
    uint32_t pulse_width = DEFAULT_PULSE_WIDTH;
    uint32_t base_control;
    uint32_t count;
    uint32_t status = 0u;
    int saw_busy = 0;
    char *cursor = arguments;

    if (!parse_u32(&cursor, &test_id)) {
        uart_puts("ERR RUN code=BAD_ID\r\n");
        return;
    }
    if ((test_id < TEST_ID_MIN) || (test_id > TEST_ID_MAX)) {
        uart_puts("ERR RUN code=ID_RANGE\r\n");
        return;
    }

    cursor = skip_spaces(cursor);
    if (*cursor != '\0') {
        if (!parse_u32(&cursor, &pulse_width) ||
            !only_spaces_remain(cursor)) {
            uart_puts("ERR RUN code=BAD_PULSE\r\n");
            return;
        }
    }
    if ((pulse_width == 0u) || (pulse_width > MAX_PULSE_WIDTH)) {
        uart_puts("ERR RUN code=PULSE_RANGE\r\n");
        return;
    }

    if (!clear_generator()) {
        reply_status("ERR RUN code=CLEAR_TIMEOUT");
        return;
    }

    base_control =
        ((test_id << CONTROL_TEST_ID_SHIFT) & CONTROL_TEST_ID_MASK) |
        ((pulse_width << CONTROL_PULSE_SHIFT) & CONTROL_PULSE_MASK);

    /*
     * Keep TEST_ID/PULSE stable and create an explicit START_LEVEL 0->1->0
     * sequence.  Each AXI write completes before the following write.
     */
    mmio_write32(AXI_GPIO_BASE + GPIO_DATA_OFFSET, base_control);
    mmio_write32(AXI_GPIO_BASE + GPIO_DATA_OFFSET,
                 base_control | CONTROL_START_LEVEL);
    mmio_write32(AXI_GPIO_BASE + GPIO_DATA_OFFSET, base_control);
    last_control = base_control;

    for (count = 0u; count < RUN_TIMEOUT_POLLS; ++count) {
        status = gpio_status();
        if ((status & STATUS_BUSY) != 0u) {
            saw_busy = 1;
        }
        if ((status & STATUS_DONE) != 0u) {
            uart_puts("OK RUN id=");
            uart_putc((char)('0' + test_id));
            uart_puts(" pulse=");
            uart_put_hex32(pulse_width);
            uart_puts(" saw_busy=");
            uart_putc(saw_busy ? '1' : '0');
            uart_puts(" status=");
            uart_put_hex32(status);
            uart_puts("\r\n");
            return;
        }
    }

    uart_puts("ERR RUN id=");
    uart_putc((char)('0' + test_id));
    uart_puts(" code=TIMEOUT saw_busy=");
    uart_putc(saw_busy ? '1' : '0');
    uart_puts(" status=");
    uart_put_hex32(status);
    uart_puts("\r\n");
}

static void process_command(char *line)
{
    char *command = skip_spaces(line);
    char *arguments;

    if (*command == '\0') {
        return;
    }

    arguments = command;
    while ((*arguments != '\0') &&
           (*arguments != ' ') && (*arguments != '\t')) {
        ++arguments;
    }
    if (*arguments != '\0') {
        *arguments = '\0';
        ++arguments;
    }
    arguments = skip_spaces(arguments);

    if (token_equals(command, "PING") && only_spaces_remain(arguments)) {
        uart_puts("OK PONG\r\n");
    } else if (token_equals(command, "STATUS") &&
               only_spaces_remain(arguments)) {
        reply_status("OK STATUS");
    } else if (token_equals(command, "CLEAR") &&
               only_spaces_remain(arguments)) {
        command_clear();
    } else if (token_equals(command, "RUN")) {
        command_run(arguments);
    } else if (token_equals(command, "HELP") &&
               only_spaces_remain(arguments)) {
        uart_puts("OK HELP commands=PING|STATUS|CLEAR|RUN_<id>_[pulse]|HELP"
                  "\r\n");
    } else {
        uart_puts("ERR code=BAD_COMMAND\r\n");
    }
}

int main(void)
{
    char line[COMMAND_BUFFER_SIZE];
    uint32_t length = 0u;
    int overflow = 0;

    /* AXI GPIO channel 1 is all-output; channel 2 is all-input. */
    mmio_write32(AXI_GPIO_BASE + GPIO_TRI_OFFSET, 0u);
    mmio_write32(AXI_GPIO_BASE + GPIO_TRI2_OFFSET, 0xFFFFFFFFu);
    mmio_write32(AXI_GPIO_BASE + GPIO_DATA_OFFSET, 0u);
    last_control = 0u;

    /* Drop stale bytes from both FIFOs before announcing readiness. */
    mmio_write32(AXI_UARTLITE_BASE + UART_CONTROL_OFFSET,
                 UART_CONTROL_RESET_TX | UART_CONTROL_RESET_RX);

    uart_puts("EdgeScope-Lite ILA Runtime Control v1\r\n");
    uart_puts("READY baud=9600 gpio=0x40000000 uart=0x40600000\r\n");

    for (;;) {
        char character = uart_getc_blocking();

        if ((character == '\r') || (character == '\n')) {
            if (overflow) {
                uart_puts("ERR code=LINE_TOO_LONG\r\n");
            } else if (length != 0u) {
                line[length] = '\0';
                process_command(line);
            }
            length = 0u;
            overflow = 0;
        } else if (!overflow) {
            if (length < (COMMAND_BUFFER_SIZE - 1u)) {
                line[length] = character;
                ++length;
            } else {
                overflow = 1;
            }
        }
    }
}
