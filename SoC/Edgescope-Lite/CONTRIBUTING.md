# Contributing to EdgeScope-Lite

팀원은 `main`에 직접 기능 Commit을 쌓지 않고, 담당 기능 브랜치와 Pull
Request를 사용합니다.

## 권장 브랜치

- `feature/firmware-protocol`: Vitis Compact Hex `@ESL` Protocol
- `feature/web-dashboard`: Chrome Web Serial UI와 Mock Data
- `feature/gui-integration`: 실제 Basys3 연결, Retry와 재접속
- `fix/<short-name>`: 독립적인 결함 수정
- `docs/<short-name>`: 문서만 수정

한 브랜치는 한 가지 목적만 가져야 합니다. 공유 브랜치에서 여러 사람이
동시에 같은 파일을 직접 수정하지 않습니다.

## 파일 소유와 교차검토

| 영역 | 주 작업자 | 필수 검토자 |
|---|---|---|
| `rtl/`, `ip_repo/` | RTL 담당 | 검증 담당 |
| `sim/`, `scripts/run_regression.sh` | 검증 담당 | RTL 담당 |
| `sw/vitis_app/` | Firmware 담당 | GUI/통합 담당 |
| `dashboard/` | GUI 담당 | Firmware 담당 |
| `sw/include/logic_analyzer_regs.h` | 공용 사양 담당 | RTL + Firmware |

`sw/include/logic_analyzer_regs.h`는 RTL과 Software 사이의 ABI입니다.
Offset, Bit, Depth 또는 Trigger Index 변경은 반드시 공통 명세와 RTL/C
검증을 함께 갱신해야 합니다.

## 작업 순서

```bash
git switch main
git pull --ff-only
git switch -c feature/<name>
```

작업 뒤 관련 검사를 실행하고 원격 브랜치에 Push한 다음 `main` 대상 Draft
Pull Request를 만듭니다. 다른 팀원이 검증 결과를 확인한 뒤 Ready for
review로 전환합니다.

## Pull Request 검증

변경 영역에 맞는 항목을 PR 본문에 기록합니다.

- RTL: `./scripts/run_regression.sh`
- RTL 파형: `./scripts/run_regression.sh --waves`
- Vitis C: `-Wall -Wextra -Werror` Build
- Protocol: Frame count, Offset, Length, Checksum
- Dashboard: Mock Rising/Falling/Pattern 및 Timeout/Retry
- Board: UART 로그 또는 화면 녹화

## Commit과 생성물

- Commit 제목은 현재형의 짧은 설명으로 작성합니다.
- Vivado/Vitis Build, cache, XSA, bitstream, ELF와 개인 절대경로는
  Commit하지 않습니다.
- 발표·검증용 VCD는 기존 정책대로 `artifacts/waves/`만 예외입니다.
- Token, Serial Number, 개인 계정 정보와 로컬 Device 권한 설정을
  Commit하지 않습니다.
