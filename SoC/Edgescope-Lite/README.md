# EdgeScope-Lite Logic Analysis

Basys3의 MicroBlaze SoC에서 사용하는 8-channel standalone logic analyzer
프로젝트입니다.

팀 구현의 단일 기준 문서는 Frozen v2.1
[docs/day1_common_spec.md](docs/day1_common_spec.md)입니다.

다른 Vivado/Vitis 2024.2 PC에서 Clone, 환경 점검, A/B/C 프로그램과
전체 재빌드를 수행하는 방법은
[다른 PC 실행 가이드](docs/portable_setup.md)에 정리되어 있습니다.

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
├── dashboard/      역할 B Mock/Web Serial 파형 Dashboard
└── sw/
    └── include/    Vitis register header
```

일반 generated output과 Vivado cache는 Git에 포함하지 않습니다. 보드에서
즉시 실행할 수 있는 검증된 A/B/C XSA·ELF·Bootable Bitstream,
checksum-bound ILA 증거와 `artifacts/waves/*.vcd`만 예외로 공유합니다.

## 역할 B — Chrome Web Serial Dashboard

역할 B의 TypeScript/Vite Dashboard는 [dashboard/README.md](dashboard/README.md)에
기능과 실행법이 정리되어 있으며 현재 `main`에서 바로 실행할 수 있습니다.

```bash
cd dashboard
npm ci
npm run lint
npm test
npm run build
npm run dev
```

Windows PowerShell에서는 `npm.cmd`를 사용할 수 있습니다. 다른 PC의
VS Code로 옮기는 전체 절차, 검증한 Node/npm 버전과 Live Parser 경계는
[역할 B VS Code 이관 체크리스트](docs/role_b_vscode_migration.md)를
참조합니다.

## 비교군 A — CPU Polling Reference

MicroBlaze V가 AXI GPIO를 반복해서 읽는 Software Polling 기준군은
[comparison/cpu_polling/README.md](comparison/cpu_polling/README.md)에 정리되어
있습니다.

- Basys3 실측 대표 처리량: `1,666,666 observations/s`
- Rising/Falling/Masked Pattern/Zero Mask 시험: 모두 PASS
- 10 ns·100 ns Pulse: `0/10`
- 1 µs 이상 Pulse: `10/10`
- 재현 가능한 Vivado/Vitis 스크립트, XSA, ELF, Bootable Bitstream 포함
- UART 원본 로그, Utilization/Timing/DRC 보고서 포함

세 비교군의 공통 입력 Generator와 Base SoC는 `comparison/common/`에 있으며,
동결 조건은
[docs/team_a_cpu_polling_comparison_conditions.md](docs/team_a_cpu_polling_comparison_conditions.md)를
참조합니다.

## 비교군 B — EdgeScope-Lite Hardware Capture

FPGA Sampler/Trigger/Trace Buffer와 dual-port BRAM을 공통 Base SoC에 통합한
보드 실행 패키지는
[`comparison/edgescope_lite/README.md`](comparison/edgescope_lite/README.md)에
정리되어 있습니다.

- Sampler/Trigger/Trace의 독립 AXI4-Lite CSR
- 100 MHz hardware sampling, 1,024-sample BRAM capture
- Vivado 2024.2 XSA/Bitstream 빌드 통과
- Vitis 2024.2 Release `-O2` ELF 및 Bootable Bitstream 생성
- Python GUI에서 A/B 파형과 처리량 비교

## 비교군 C — Vivado ILA Reference

동일 Base SoC와 Generator에 100 MHz, 8-bit, 1,024-sample Vivado ILA를
연결한 기준군은
[`comparison/vivado_ila/README.md`](comparison/vivado_ila/README.md)에
정리되어 있습니다.

- Vivado ILA v6.2, Trigger logical index 512
- Rising/Falling/Masked Pattern Hardware Manager 캡처
- Vivado 2024.2 XSA/Bitstream/LTX 및 Implementation 보고서 생성
- Vitis Generator 제어 ELF와 Bootable Bitstream 생성
- Python GUI에서 A/B/C 파형, 처리량과 Pulse 결과 비교
- Vivado JTAG CSV 자동 export 및 1,024-sample 무결성 검사
- [A/B/C 통합 GUI 미리보기](docs/edgescope_abc_gui_preview.png)
- [A/B/C 비교 시연 영상 시나리오](docs/abc_demo_video_scenario.md)

### ILA 실측·Step 10 증거 패키지

`comparison/vivado_ila/`는 다른 PC에서 재빌드하기 위한 Portable 구현이고,
[comparison/ila_reference/README.md](comparison/ila_reference/README.md)는
윤형욱의 실기기 측정·검증·Step 10 증거 패키지입니다.

- 1,024 sample capture와 Rising/Falling/Masked Pattern trigger 검증
- Basys3 실기기 캡처 및 10 ns~1 µs pulse stress 결과 포함
- 공통 Base SoC와 Test Pattern Generator를 사용한 동일 조건 비교
- 자동화 스크립트, 원본 CSV/ILA, 체크섬, 발표용 SVG 포함
- 현재 상태: `PASS_WITH_TEAM_INPUT_PENDING`

ILA 자체 검증은 완료됐지만 Custom Full-System 최종 측정 7종이 아직 없어
공식 Custom 대비 절감률은 확정하지 않았습니다. 현재 결론과 팀 인수인계는
[Step 10 요약](comparison/ila_reference/results/step10/final_summary.md)과
[team_handoff.md](comparison/ila_reference/results/step10/team_handoff.md)에서
확인할 수 있습니다.

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
