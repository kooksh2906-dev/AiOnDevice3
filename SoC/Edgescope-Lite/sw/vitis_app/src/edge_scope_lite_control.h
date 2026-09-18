#ifndef EDGE_SCOPE_LITE_CONTROL_H
#define EDGE_SCOPE_LITE_CONTROL_H

#include <stdint.h>

/*
 * 함수 반환값
 *
 * EDGE_SCOPE_OK             : 요청한 동작이 정상 완료됨
 * EDGE_SCOPE_ERR_INVALID_ARG: Divider, Trigger Mode 등의 인자가 범위를 벗어남
 * EDGE_SCOPE_ERR_TIMEOUT    : 지정한 Polling 횟수 안에 상태가 바뀌지 않음
 * EDGE_SCOPE_ERR_NOT_DONE   : Capture 완료 전에 BRAM Dump를 요청함
 * EDGE_SCOPE_ERR_HW_STATE   : 예상과 달리 Capture가 동작 중이 아닌 상태가 됨
 * EDGE_SCOPE_ERR_DATA_CHANGED: 보존돼야 할 Capture BRAM 데이터가 변경됨
 * EDGE_SCOPE_ERR_DATA_MISMATCH: Capture 데이터가 기대 파형과 일치하지 않음
 */
typedef enum {
    EDGE_SCOPE_OK                =  0,
    EDGE_SCOPE_ERR_INVALID_ARG   = -1,
    EDGE_SCOPE_ERR_TIMEOUT       = -2,
    EDGE_SCOPE_ERR_NOT_DONE      = -3,
    EDGE_SCOPE_ERR_HW_STATE      = -4,
    EDGE_SCOPE_ERR_DATA_CHANGED  = -5,
    EDGE_SCOPE_ERR_DATA_MISMATCH = -6
} edge_scope_result_t;

/*
 * Capture 종료 후 확인할 주요 상태와 주소를 한 번에 보관하는 구조체
 */
typedef struct {
    uint32_t status;
    uint32_t start_addr;
    uint32_t trigger_addr;
    uint32_t write_addr;
    uint32_t depth;
    uint32_t trigger_index;
    uint32_t trigger_count;
} edge_scope_capture_meta_t;

/*
 * Physical BRAM 전체 비교 결과
 *
 * mismatch_count가 0이면 나머지 세 Field는 진단에 사용하지 않는다.
 * first_mismatch_index는 START_ADDR 기준 Logical Index가 아니라
 * BRAM의 Physical Word Index이다.
 */
typedef struct {
    uint32_t mismatch_count;
    uint32_t first_mismatch_index;
    uint32_t expected_word;
    uint32_t actual_word;
} edge_scope_trace_diff_t;

/*
 * Edge Capture 전체 자동 검사 결과
 *
 * first_mismatch_index는 START_ADDR 기준 시간순 Logical Index이다.
 * window_sample_*에는 BRAM Word의 실제 Probe 값 [7:0]을 저장한다.
 */
typedef struct {
    uint32_t mismatch_count;
    uint32_t first_mismatch_index;
    uint32_t expected_word;
    uint32_t actual_word;
    uint32_t window_sample_511;
    uint32_t window_sample_512;
    uint32_t window_sample_513;
} edge_scope_trace_check_t;

/* Probe Sampler 제어 함수 */
void sampler_stop_and_clear(void);
edge_scope_result_t sampler_config(uint32_t divider_sel,
                                   uint8_t channel_mask);
void sampler_enable(void);
void sampler_disable(void);
uint32_t sampler_control_read(void);
uint32_t sampler_config_read(void);
uint32_t sampler_last_sample_read(void);
uint32_t sampler_sample_count_read(void);
edge_scope_result_t sampler_wait_samples(uint32_t additional_sample_count,
                                         uint32_t max_poll_count,
                                         uint32_t *observed_sample_count);

/* Basic Trigger Engine 제어 함수 */
void trigger_clear(void);
edge_scope_result_t trigger_config(uint32_t mode,
                                   uint32_t edge_channel,
                                   uint8_t pattern_value,
                                   uint8_t pattern_mask);
void trigger_arm(void);
uint32_t trigger_config_read(void);
uint32_t trigger_pattern_read(void);
uint32_t trigger_status_read(void);
uint32_t trigger_count_read(void);

/*
 * AXI Timer0 Polling Timeout
 *
 * timeout_timer_start()의 timeout_ticks는 2 이상이어야 한다.
 * Timer는 one-shot down-count로 시작되며 CPU Interrupt는 사용하지 않는다.
 */
void timeout_timer_stop_and_clear(void);
edge_scope_result_t timeout_timer_start(uint32_t timeout_ticks);
uint32_t timeout_timer_expired(void);
uint32_t timeout_timer_status_read(void);
uint32_t timeout_timer_load_read(void);
uint32_t timeout_timer_count_read(void);
uint32_t timeout_timer_clock_hz_read(void);

/* Circular Trace Buffer 제어 및 상태 확인 함수 */
void capture_clear(void);
void capture_abort(void);
void capture_arm(void);
uint32_t capture_status_read(void);
edge_scope_result_t capture_irq_monitor_enable(void);
uint32_t capture_irq_active_read(void);
void capture_irq_acknowledge(void);
edge_scope_result_t capture_wait_pre_ready(uint32_t max_poll_count);
edge_scope_result_t capture_wait_done(uint32_t max_poll_count);
/* Trace IDLE 확인 후 IAR Acknowledge와 raw IRQ=0 확인까지 수행 */
edge_scope_result_t capture_wait_cleared(uint32_t max_poll_count);
void capture_read_meta(edge_scope_capture_meta_t *meta);

/*
 * DONE Capture의 시간순 1,024 Word를 기대 Step 파형과 완전 비교
 *
 * Logical Index 0~511은 before_sample, Trigger Index 512~1023은
 * after_sample이어야 한다. 모든 1,024 Word를 방문하며 실제 Probe 값인
 * BRAM Word[7:0]을 비교한다.
 */
edge_scope_result_t trace_validate_transition_capture(
    uint8_t before_sample,
    uint8_t after_sample,
    edge_scope_trace_check_t *check);

/*
 * DONE 상태의 Physical BRAM 1,024 Word를 저장하고 나중에 완전 비교
 *
 * snapshot_word_count는 EDGE_SCOPE_CAPTURE_DEPTH와 같아야 한다.
 * snapshot은 최소 4,096 Byte의 읽기/쓰기가 가능한 배열이어야 한다.
 * trace_snapshot_read()가 오류를 반환하면 Snapshot은 유효하지 않다.
 * trace_snapshot_verify()의 DATA_CHANGED 반환에서는 difference가 유효하며,
 * 다른 오류 반환에서는 difference를 진단에 사용하지 않는다.
 */
edge_scope_result_t trace_snapshot_read(uint32_t *snapshot,
                                        uint32_t snapshot_word_count);
edge_scope_result_t trace_snapshot_verify(
    const uint32_t *snapshot,
    uint32_t snapshot_word_count,
    edge_scope_trace_diff_t *difference);

/*
 * DONE Capture를 START_ADDR 기준 Logical Index로 읽음
 *
 * first_index부터 sample_count개의 BRAM Word[7:0]을 samples에 저장한다.
 * 요청 범위는 0~1023 안에 완전히 포함돼야 하며 Capture 전후 Metadata가
 * 동일한 경우에만 성공한다.
 */
edge_scope_result_t trace_logical_window_read(uint32_t first_index,
                                              uint32_t sample_count,
                                              uint8_t *samples);

/*
 * DONE 상태의 BRAM을 START_ADDR부터 시간순으로 읽은 FNV-1a Checksum 계산
 */
edge_scope_result_t trace_checksum_read(uint32_t *checksum);

/* Capture 데이터를 START_ADDR 기준 시간순으로 UART에 출력 */
edge_scope_result_t trace_dump_hex(void);

#endif
