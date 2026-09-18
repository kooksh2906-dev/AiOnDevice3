# Step 9 — 구현 자원 및 타이밍 비교

- 전체 상태: `PASS_WITH_TEAM_INPUT_PENDING`
- 비교 단위: 동일한 `base_soc_wrapper` 전체 Routed SoC (`xc7a35tcpg236-1`, Vivado 2024.2, `sys_clock` 10.000 ns)
- 표의 `TOTAL_WHOLE_ROUTED_SOC`와 `DELTA_VS_COMMON_BASE_PLUS_GENERATOR`는 서로 다른 값이다.
- RAMB36과 RAMB18은 별도 보존하며, Tile 환산값은 참고값이다.
- WNS는 10.000 ns 제약에서의 여유시간이며 Fmax로 환산하지 않았다.

## 검증된 전체 Routed 결과

| 비교군 | 상태 | LUT | LUT Logic | LUT Memory | FF | RAMB36 | RAMB18 | WNS (ns) | TNS (ns) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Common Base + Generator | VERIFIED | 2685 | 2547 | 138 | 2455 | 32 | 0 | 1.313 | 0.000 |
| CPU Polling | VERIFIED | 2782 | 2644 | 138 | 2560 | 32 | 0 | 0.939 | 0.000 |
| Vivado ILA | VERIFIED | 3726 | 3500 | 226 | 4230 | 32 | 1 | 1.544 | 0.000 |
| EdgeScope Custom | NOT_RECEIVED | NA | NA | NA | NA | NA | NA | NA | NA |

## 해석 제한

- CPU Polling은 기능·성능 비교용 참조군이다. CPU 수치를 Custom-vs-ILA 공식 자원 절감률 계산에 사용하지 않는다.
- ILA의 `ila_reference_0`와 `dbg_hub` 계층 합은 계층 귀속값이다. 합성 최적화 때문에 전체 SoC 증분과 같은 값으로 간주하지 않는다.
- Custom 전체 Routed 리포트가 아직 없으므로 공식 Custom-vs-ILA 절감률은 `PENDING_CUSTOM`이다. `NA`를 0으로 해석하지 않는다.

## 다음 입력

`results/step9/inputs/custom/`에 동일 조건의 `utilization.rpt`, `hierarchical_utilization.rpt`, `timing_summary.rpt`, `route_status.rpt`, `drc.rpt`, `routed_design.dcp`, `build_manifest.rpt`가 필요하다.
