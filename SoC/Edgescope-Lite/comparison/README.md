# EdgeScope-Lite 비교 실험

이 디렉터리는 동일한 Basys3 입력 조건에서 세 구현을 비교하기 위한 자료다.

| 구분 | 구현 | 역할 |
|---|---|---|
| A | CPU Polling Reference | Software Polling 성능·검출 한계 기준 |
| B | EdgeScope-Lite Custom IP | 팀이 구현한 Standalone Logic Analyzer |
| C | Vivado ILA | Xilinx Hardware Analyzer 기준 |

현재 이 디렉터리에는 보드 실측을 완료한 A, 구현·빌드를 완료한 B/C와 세
비교군이 공유하는 Base SoC 및 Test Pattern Generator가 포함되어 있다. B/C의
실제 trigger·Pulse 측정값은 Basys3에서 원본 UART/JTAG 캡처를 얻은 뒤 확정한다.

## 주요 경로

- `common/base_soc.tcl`: 세 비교군 공통 MicroBlaze V SoC
- `common/rtl/test_pattern_generator.sv`: 동일 입력을 만드는 공통 Generator
- `cpu_polling/`: 비교군 A의 Vivado, Vitis, 보고서 및 실측 결과
- `edgescope_lite/`: 비교군 B의 Custom Analyzer 전체 빌드
- `vivado_ila/`: 비교군 C의 Vivado ILA 전체 빌드와 JTAG 캡처 자동화

비교군 A는 기능적으로 100 MS/s Hardware Analyzer와 동등하지 않다. 따라서 A의
처리량은 `observations/s`로 표기하며, 공식 자원 절감률은 기능적으로 동등한
EdgeScope-Lite Custom IP와 Vivado ILA 사이에서만 계산한다.
