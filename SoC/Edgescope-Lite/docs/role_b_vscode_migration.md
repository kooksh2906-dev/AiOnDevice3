# 역할 B Web Dashboard — 다른 PC/VS Code 이관 체크리스트

이 문서는 역할 B의 TypeScript/Chrome Web Serial Dashboard를 새 PC에서
그대로 이어서 개발하고 검증하기 위한 기록이다. FPGA A/B/C 비교용 Python
GUI 이관은 [portable_setup.md](portable_setup.md)를 사용한다.

## 1. 현재 단일 기준

| 항목 | 기준 |
|---|---|
| GitHub | `https://github.com/yoon3226/EdgeScope-Lite-SoC` |
| 역할 B Branch | `feature/web-dashboard` |
| Draft PR | [#5 Build Web Serial waveform dashboard](https://github.com/yoon3226/EdgeScope-Lite-SoC/pull/5) |
| 최초 역할 B 구현 Commit | `0ebcc0863439673c9241d9e3cc33801f656de9df` |
| 앱 경로 | `dashboard/` |
| 상세 사용법 | [dashboard/README.md](../dashboard/README.md) |

2026-07-30 현재 역할 B Dashboard는 Draft PR에 있고 `main`에는 아직 없다.
PR 병합 전 새 PC에서는 반드시 `feature/web-dashboard`를 체크아웃한다. PR이
병합된 뒤에는 최신 `main`을 사용한다.

이 저장소에는 이름이 비슷한 GUI가 두 개 있으므로 구분한다.

| GUI | 경로/실행 | 용도 |
|---|---|---|
| A/B/C 통합 비교 GUI | `python3 scripts/cpu_polling_gui.py`, port 8765 | Ubuntu/Vivado 비교 시연 |
| 역할 B Web Dashboard | `dashboard/`, port 4173 | Mock-first Chrome Web Serial 파형 UI |

## 2. 검증한 개발 환경

| 도구 | 검증 값 | 요구사항 |
|---|---:|---|
| Windows PowerShell | 5.1 | Windows 빠른 시작 기준 |
| Git | 2.54.0.windows.1 | 일반 최신 Git |
| VS Code | 1.127.0 x64 | 저장소 루트를 Workspace로 열기 |
| Node.js | **24.16.0** | `package.json`은 20.19+, 22.12+ 또는 24+ 지원 |
| npm | **11.13.0** | `package-lock.json` 기준 `npm ci` 사용 |
| Chrome | 150.0.7871.187 | 데스크톱 Chrome, Web Serial 지원 |

`dashboard/.node-version`은 실제 검증한 Node 24.16.0을 기록한다. 다른
지원 Node를 사용하더라도 `npm ci`, lint, test와 build를 모두 다시
통과시켜야 한다.

## 3. Clone과 Branch 선택

GitHub Token이나 기존 PC의 Credential 파일을 복사하지 않는다. 새 PC에서
Git Credential Manager의 브라우저 로그인으로 다시 인증한다. GitHub CLI는
필수 조건이 아니다.

```powershell
git clone https://github.com/yoon3226/EdgeScope-Lite-SoC.git
cd EdgeScope-Lite-SoC
git switch --track origin/feature/web-dashboard
code .
```

GitHub CLI를 별도로 설치해 사용하는 경우에만 Clone 전에 `gh auth login`을
실행해도 된다.

로컬 Branch가 이미 만들어졌다면 마지막 Git 명령은 다음으로 충분하다.

```powershell
git switch feature/web-dashboard
git pull --ff-only
```

PR 병합 후 새로 Clone하는 경우에는 `git switch main`을 사용한다.

## 4. Windows PowerShell 빠른 시작

이 PC에서는 PowerShell Execution Policy 때문에 `npm.ps1`이 차단될 수
있었다. 전역 Execution Policy를 바꾸지 않고 `npm.cmd`를 사용하면 된다.

```powershell
cd dashboard
node --version
npm.cmd --version
npm.cmd ci
npm.cmd run lint
npm.cmd test
npm.cmd run build
npm.cmd run dev
```

Chrome에서 `http://127.0.0.1:4173`을 연다. `index.html`을 `file://`로
직접 열거나 VS Code Simple Browser/Live Server로 우회하지 않는다.

port 4173은 `strictPort`다. 이미 사용 중이면 Vite가 다른 port를 자동으로
선택하지 않고 종료하므로, 기존 Dashboard dev/preview 프로세스를 확인한 뒤
종료하고 다시 실행한다.

Linux/macOS에서는 같은 위치에서 `npm ci`, `npm run ...`을 사용한다.
최초 `npm ci`에는 npm registry에 접근할 인터넷 연결이 필요하다.

## 5. VS Code 설정

저장소 루트의 `.vscode/`에는 다음만 공유한다.

- Workspace TypeScript: `dashboard/node_modules/typescript/lib`
- Dashboard install/lint/test/build/dev/preview Task
- 선택 사항인 Vitest Explorer 추천

VS Code에서 `Terminal > Run Task`를 열면 `Dashboard: ...` Task를 실행할
수 있다. Theme, 개인 Terminal profile, GitHub Token, 장치 COM 번호와
사용자 절대경로는 저장소에 기록하지 않는다.

## 6. Mock 인수 점검

`npm.cmd run dev` 뒤 다음 순서로 확인한다.

1. `Mock fixture`와 Demo/Scenario를 선택한다.
2. `연결` → `WAIT_START`에서 `Capture 시작 (s)`를 누른다.
3. `GO`에서만 Trigger 조작 안내가 보이는지 확인한다.
4. `WAIT_FREEZE`에서 `Freeze 완료 (f)`를 누른다.
5. Rising, Falling, Pattern의 1,024 Sample과 Validation PASS를 확인한다.
6. Timeout과 `검증 거부 · CRC 모의`가 이전 정상 파형을 유지하는지 확인한다.
7. 전체 화면과 Trigger 확대 `[448,576)`에서 marker가 index 512 경계인지
   확인한다.

기준 화면은
[role_b_dashboard_1366x768.png](role_b_dashboard_1366x768.png)이다.

## 7. Live Web Serial의 현재 경계

Live Port는 데스크톱 Chrome의 `http://127.0.0.1:4173`에서 선택한다.
다른 Serial Monitor, VS Code Serial Monitor, PuTTY, Tera Term과 Vitis
Terminal은 모두 닫아 한 프로그램만 COM Port를 연다.

```text
9,600 baud
8 data bits
1 stop bit
parity none
flow control none
```

현재 Composition Root는 `PendingProtocolBridge`를 사용한다. 따라서
역할 C의 승인된 `docs/uart_protocol_v1.md`, Parser/Assembler와 역할 A의
Compact Frame Firmware가 병합되기 전에는:

- Connect/Disconnect, 연결 직후 자동 `?` 전송과 Raw Log까지만 현재 Live
  범위다.
- `s`, `f`와 수동 Sync는 역할 C Parser가 STATE를 만들어 준 뒤에만
  활성화되며, 현재 버튼이 비활성인 것은 이관 실패가 아니다.
- Live Byte가 검증된 파형으로 바뀌지 않는 것은 의도된 동작이다.
- 실제 Basys3 파형과 CRC/FNV 인수시험은 역할 A/C 병합 후 수행한다.

Windows에서 Basys3 COM Port가 보이지 않으면 보드 전원, USB cable,
Digilent/Vivado cable driver와 장치 관리자를 확인한다.

## 8. 옮기지 않아도 되는 파일

다음은 Git에서 의도적으로 제외되며 새 PC에서 재생성한다.

```text
dashboard/node_modules/
dashboard/dist/
dashboard/coverage/
dashboard/*.tsbuildinfo
.npm-cache/
```

`.git/` 폴더, GitHub/Google OAuth Token, VS Code 개인 User Settings,
Chrome Profile과 실제 COM Port 이름도 복사하지 않는다. Dashboard에는
별도 `.env`나 Secret이 필요하지 않다.

소스, `package-lock.json`, 테스트와 설정은 GitHub Branch가 단일 기준이다.
Google Drive ZIP은 비상 백업이며 GitHub보다 우선하지 않는다.

## 9. 이관 완료 조건

- [ ] `git status -sb`가 의도한 Branch와 깨끗한 작업 트리를 표시한다.
- [ ] Node/npm 버전을 확인하고 `npm ci`가 완료된다.
- [ ] `npm run lint`의 TypeScript 검사, 37개 test와 production build가 PASS다.
- [ ] Chrome 1366×768에서 세 Mock Demo와 오류 보존 동작을 확인한다.
- [ ] Live가 역할 C Parser 전에는 Raw Log 전용임을 인수자에게 전달한다.
- [ ] 새 PC에서 GitHub 인증을 다시 설정하고 Token 파일은 복사하지 않는다.
