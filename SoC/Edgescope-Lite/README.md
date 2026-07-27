# EdgeScope-Lite Logic Analysis

Basys3의 MicroBlaze SoC에서 사용하는 8-channel standalone logic analyzer
프로젝트입니다.

팀 구현의 단일 기준 문서는 Frozen v2.1
[docs/day1_common_spec.md](docs/day1_common_spec.md)입니다.

## 동결 사양

- 8-bit probe, 100 MHz
- Divider 1/2/4/8
- Rising/Falling/Masked Pattern trigger 중 하나
- 1,024 × 32-bit dual-port BRAM
- 512 pre-trigger + trigger 포함 512 post-trigger
- Trigger logical index 512
- AXI4-Lite register는 IP별 독립 base address 사용

## 팀 공유 파일

| 대상 | 파일 |
|---|---|
| 전 팀원 | `docs/day1_common_spec.md` |
| RTL 담당자 | `rtl/include/logic_analyzer_pkg.sv` |
| Vitis C 담당자 | `sw/include/logic_analyzer_regs.h` |

## 폴더 구조

```text
Logic Analysis/
├── docs/           공통 명세, IP 데이터시트
├── rtl/
│   ├── core/       세 Custom IP core
│   ├── bus/        IP별 AXI4-Lite wrapper
│   ├── include/    공통 package
│   └── top/        통합 및 supporting RTL
├── sim/
│   ├── tb/         IP별 testbench
│   └── vectors/    scoreboard 입력/기대값
├── constraints/    XDC
├── scripts/        simulation, lint, build
└── sw/
    └── include/    Vitis register header
```

일반 generated output, Vivado cache와 bitstream은 Git에 포함하지 않습니다.
최종 검증 증거인 `artifacts/waves/*.vcd`만 예외로 공유합니다.

## 회귀 테스트

```bash
./scripts/run_regression.sh
./scripts/run_regression.sh --waves
```

두 번째 명령은 동일한 7개 SystemVerilog/C 검증을 실행하고
`artifacts/waves/`에 발표·상호검토용 VCD를 생성합니다.

## 윤형욱 최종 산출물

| 문서 | 링크 |
|---|---|
| 1페이지 IP 데이터시트 | [docs/circular_trace_buffer_datasheet.md](docs/circular_trace_buffer_datasheet.md) |
| Steps 1–9 감사/검증 | [docs/verification_report.md](docs/verification_report.md) |
| 실제 VCD 기반 파형 | [docs/circular_trace_buffer_waveform.png](docs/circular_trace_buffer_waveform.png) |
| 발표 슬라이드/대본 | [docs/yoon_hyungwook_presentation.md](docs/yoon_hyungwook_presentation.md) |
| 팀 통합 인수인계 | [docs/yoon_hyungwook_handoff.md](docs/yoon_hyungwook_handoff.md) |
| Step 10 완료표 | [docs/step10_final_delivery.md](docs/step10_final_delivery.md) |
