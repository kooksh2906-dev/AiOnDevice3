# Step 10 — Vivado ILA 증거·발표 패키지

상태: **검증된 Draft — Custom 전체 Routed 자료 대기**

## 결론

윤형욱 담당 Vivado ILA 비교군은 보드 기능시험, CSV 정규화, Pulse Stress,
전체 Routed 자원·Timing 검증까지 독립적으로 통과했다. 현재 패키지 모드는
`DRAFT`이며, Step 9 상태는 `PASS_WITH_TEAM_INPUT_PENDING`이다.

팀의 Custom 전체 Routed 7개 파일이 아직 없으므로 Custom-vs-ILA 공식 절감률은 계산하지 않았고, 빈 값을 0으로 대체하지 않았다.

## 검증 결과

| 항목 | 결과 | 근거 |
|---|---:|---|
| ILA 설정 | 100 MHz, 8-bit, Depth 1,024, Trigger 512 | Step 6 Readback |
| Rising / Falling / Pattern | 3종 모두 PASS | 실제 Basys 3 Capture |
| No-trigger 100 ms | PASS, Partial Capture 0 | 실제 Basys 3 Capture |
| 정규화 CSV | 3종 × 1,024행 무손실 PASS | Step 7 Validator |
| Pulse Stress | 6개 폭 × 10회 = **60/60** | 10 ns–1 ms 동기 Pulse |
| ILA 전체 Routed 자원 | LUT 3,726, FF 4,230, RAMB36/18 32/1 | Vivado 2024.2 |
| ILA 순증가량 | LUT +1,041, FF +1,775, RAMB18 +1 | Common Base+Generator 대비 |
| ILA Timing | WNS +1.544 ns, TNS 0.000 ns | 10.000 ns 제약 |
| Custom 공식 절감률 | `PENDING_CUSTOM` | CPU Polling은 산식에서 제외 |

## 비교표

| 방식 | 상태 | LUT | FF | RAMB36 | RAMB18 | WNS |
|---|---|---:|---:|---:|---:|---:|
| Common Base + Generator | VERIFIED | 2,685 | 2,455 | 32 | 0 | 1.313 ns |
| CPU Polling | VERIFIED | 2,782 | 2,560 | 32 | 0 | 0.939 ns |
| Vivado ILA | VERIFIED | 3,726 | 4,230 | 32 | 1 | 1.544 ns |
| EdgeScope Custom | NOT_RECEIVED | NA | NA | NA | NA | NA |

## 발표 시 해석 제한

- WNS는 100 MHz 제약의 여유시간이다. WNS로 Fmax를 계산하거나 순위를
  만들지 않는다.
- CPU Polling은 Software 관찰 기준군이며 공식 Custom-vs-ILA 절감률 산식에
  넣지 않는다.
- Trigger Index 512는 Trigger Sample을 포함한 Post-trigger 512개를 뜻한다.
- No-trigger 시험에 정상 1,024-Sample Capture가 없는 것은 정상 결과다.
- 10 ns Pulse 결과는 공통 100 MHz Generator와 ILA가 동기인 동결 시험의
  결과이며, 임의 비동기 Pulse 전체에 일반화하지 않는다.

## 무결성

- Step 5~9 Checksum Manifest 6개 검증
- Manifest가 결속한 파일 총 305개 검증
- GitHub 원격 `main` 감사 Commit: `c41254682dee66bbb5cea763641ba20aebd94e58`
- 원격 코드 자동 시험: `PASS`
- Final Demo 실제 XSA 매크로 호환: `FAIL`
- 이 폴더의 최종 파일은 `SHA256SUMS`로 다시 검증 가능
