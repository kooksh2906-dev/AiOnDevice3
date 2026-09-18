# 다른 PC에서 A/B/C 시연 실행하기

이 문서는 새 Ubuntu PC에서 저장소를 Clone한 뒤 A CPU Polling,
B EdgeScope-Lite, C Vivado ILA와 통합 GUI를 재현하는 절차다.

## 1. 지원 환경

| 항목 | 요구사항 |
|---|---|
| FPGA board | Digilent Basys3 |
| FPGA part | `xc7a35tcpg236-1` |
| Board part | `digilentinc.com:basys3:part0:1.2` |
| Vivado/Vitis | `2024.2` |
| Processor | MicroBlaze RISC-V |
| Host | Ubuntu Linux, Python 3.10 이상 |
| UART | 9,600 baud, 8-N-1 |

Vivado 설치 시 Artix-7 device support, MicroBlaze RISC-V IP와 cable
driver를 포함해야 한다. 다른 Vivado 버전이 함께 설치되어 있어도 이
프로젝트의 공식 Build와 C ILA 캡처에는 2024.2를 사용한다.

## 2. 비공개 저장소 Clone

GitHub CLI를 사용하는 방법:

```bash
gh auth login
gh repo clone yoon3226/EdgeScope-Lite-SoC
cd EdgeScope-Lite-SoC
```

이미 GitHub HTTPS 또는 SSH 인증이 설정되어 있다면 일반 `git clone`도
사용할 수 있다.

```bash
git clone https://github.com/yoon3226/EdgeScope-Lite-SoC.git
cd EdgeScope-Lite-SoC
```

## 3. 도구 환경과 Python 준비

설치 위치에 맞게 2024.2 환경을 불러온다.

```bash
source <Xilinx-root>/Vivado/2024.2/settings64.sh
source <Xilinx-root>/Vitis/2024.2/settings64.sh
export VIVADO="$(command -v vivado)"
```

`VIVADO`는 설치 디렉터리가 아니라 실제 실행 파일 경로여야 한다.

```text
/tools/Xilinx/Vivado/2024.2/bin/vivado
```

GUI용 가상환경을 만든다.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements-gui.txt
```

Ubuntu에 C compiler가 없다면 `build-essential`도 설치한다.

```bash
sudo apt update
sudo apt install build-essential make usbutils
```

## 4. Basys3 board files

Vivado에서 다음 Board Part가 보이는지 확인한다.

```text
digilentinc.com:basys3:part0:1.2
```

스크립트는 이미 로드된 Board Part, `EDGESCOPE_BOARD_REPO`, XHub와
일반적인 Vivado 설치 경로 순으로 board repository를 탐색한다. 자동으로
찾지 못하면 Basys3 `board_files`의 상위 디렉터리를 지정한다.

```bash
export EDGESCOPE_BOARD_REPO=/path/to/board_files
```

Linux에서 UART 권한이 없으면 사용자를 `dialout` 그룹에 추가한 뒤
로그아웃하고 다시 로그인한다.

```bash
sudo usermod -aG dialout "$USER"
```

JTAG가 인식되지 않으면 Vivado 2024.2와 함께 제공되는 Digilent cable
driver가 설치되었는지 확인한다.

## 5. 사전 점검

```bash
./scripts/check_portable_environment.sh
```

다음 항목을 검사한다.

- Vivado/Vitis/updatemem/XSim과 C compiler
- Vivado 정확한 버전
- Python과 pyserial
- A/B/C Bootable Bitstream 및 C LTX
- Board repository override
- JTAG USB와 UART 장치

보드가 연결되지 않은 경우 JTAG/UART는 `WARN`이며 GUI DEMO는 실행할 수
있다. 도구 또는 필수 산출물이 없으면 `FAIL`이다.

## 6. 보드 없이 GUI 확인

```bash
python3 scripts/cpu_polling_gui.py
```

브라우저에서 `http://127.0.0.1:8765`를 연다. `데모 모드`에서는:

- A: 저장된 Basys3 UART 실측 결과
- B/C: `DEMO · SYNTHETIC` 미리보기
- A/B/C Implementation: 실제 Vivado Report 값

을 확인할 수 있다. DEMO 배지가 있는 B/C 값을 실측이라고 표현하지 않는다.

## 7. 체크인된 Bitstream으로 즉시 실행

한 번에 하나의 Basys3만 연결하는 구성이 가장 안전하다. 비교군을 바꿀
때마다 Bitstream 프로그램, UART 재연결, READY 확인 순서를 지킨다.

A:

```bash
vivado -mode batch \
  -source comparison/cpu_polling/vitis/program_bitstream.tcl
```

B:

```bash
vivado -mode batch \
  -source comparison/edgescope_lite/vitis/program_bitstream.tcl
```

C:

```bash
vivado -mode batch \
  -source comparison/vivado_ila/vitis/program_bitstream.tcl
```

여러 Digilent target이 연결되어 있으면 정확한 Hardware Target을 지정한다.

```bash
export EDGESCOPE_HW_TARGET='*/xilinx_tcf/Digilent/<target-name>'
```

프로그램 후 GUI에서 UART 포트를 선택하고 `연결`을 누른다. READY marker는
다음과 같다.

| 비교군 | READY marker |
|---|---|
| A | `CPU_POLLING_REFERENCE_READY` |
| B | `EDGESCOPE_LITE_REFERENCE_READY` |
| C | `VIVADO_ILA_REFERENCE_READY` |

C의 Rising/Falling/Pattern/Pattern Hold 버튼은 ILA를 먼저 ARM한 뒤 UART
자극을 보낸다. 캡처 성공 시 `MEASURED · VIVADO ILA JTAG CSV`가 표시된다.

## 8. 소스에서 전체 재빌드

세 Build는 공통 Base 생성 디렉터리를 사용하므로 병렬 실행하지 않는다.
저메모리 PC에서는 다음 값을 낮춘다.

```bash
export CPU_POLL_JOBS=2
export EDGESCOPE_JOBS=2
```

먼저 회귀 시험을 실행한다. Icarus Verilog가 없으면 Vivado XSim을 자동으로
사용한다.

```bash
./scripts/run_regression.sh
./scripts/run_frontend_axi_xsim.sh
```

### A — CPU Polling

```bash
vivado -mode batch \
  -source comparison/cpu_polling/hw/block_design.tcl
vivado -mode batch \
  -source comparison/cpu_polling/hw/build_all.tcl
vitis -s comparison/cpu_polling/vitis/build_cpu_polling.py
```

### B — EdgeScope-Lite

```bash
vivado -mode batch -source scripts/package_frontend_ips.tcl
vivado -mode batch -source scripts/package_trace_buffer_ip.tcl
vivado -mode batch \
  -source comparison/edgescope_lite/hw/block_design.tcl
vivado -mode batch \
  -source comparison/edgescope_lite/hw/build_all.tcl
vitis -s comparison/edgescope_lite/vitis/build_edgescope_lite.py
```

### C — Vivado ILA

```bash
vivado -mode batch \
  -source comparison/vivado_ila/hw/block_design.tcl
vivado -mode batch \
  -source comparison/vivado_ila/hw/build_all.tcl
vitis -s comparison/vivado_ila/vitis/build_vivado_ila.py
```

Vitis Python 파일은 일반 `python3`가 아니라 반드시 `vitis -s`로 실행한다.
각 Vitis Build는 ELF뿐 아니라 프로그램 가능한 Bootable Bitstream을
`comparison/<analyzer>/vitis_artifacts/`에 생성한다.

## 9. C 캡처 설정

GUI가 Vivado를 자동으로 찾지 못하면 실행 파일을 지정한다.

```bash
export VIVADO=/path/to/Vivado/2024.2/bin/vivado
```

느린 PC에서 최초 Hardware Manager 연결이 60초를 넘는다면 watchdog을
늘린다.

```bash
export EDGESCOPE_ILA_TIMEOUT_SECONDS=120
```

C 자동 캡처 순서:

```text
Hardware Manager 연결
→ ILA ARM
→ VIVADO_ILA_ARMED
→ UART 자극
→ JTAG upload
→ CSV export
→ 1,024 sample/trigger 512 무결성 검사
→ GUI MEASURED 표시
```

## 10. 촬영 자료

- [A/B/C GUI 사용법](../comparison/cpu_polling/gui/README.md)
- [A/B/C 시연 영상 시나리오](abc_demo_video_scenario.md)
- [C Vivado ILA 상세 절차](../comparison/vivado_ila/README.md)
- [통합 GUI 화면](edgescope_abc_gui_preview.png)
