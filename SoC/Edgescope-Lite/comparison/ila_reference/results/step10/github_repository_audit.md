# GitHub 저장소 파일 감사

- 저장소: `yoon3226/EdgeScope-Lite-SoC`
- 감사 Ref: `HEAD`
- 감사 Commit: `c41254682dee66bbb5cea763641ba20aebd94e58`
- 작성자/시각: `YOON HYEONG UK` / `2026-07-30T10:22:28+09:00`
- 제목: `Resolve ILA evidence merge and restore provenance`
- 로컬 HEAD: `c41254682dee66bbb5cea763641ba20aebd94e58` (`agent/publish-ila-step10`)
- 로컬과 원격 차이: behind 0, ahead 0
- 로컬 작업 트리 변경 존재: `YES`

## 확인 결과

| 항목 | 판정 |
|---|---|
| 공통 Base SoC / Generator가 로컬 동결본과 동일 | `2/2 MATCH` |
| CPU Polling 보고서 4종이 Step 9 입력과 동일 | `4/4 MATCH` |
| 원격 `main` 자동 시험 | `PASS` |
| 기본 회귀에 신규 Sampler/Trigger TB 포함 | `FAIL` |
| Trigger TB 실패 시 Non-zero 종료 보장 | `FAIL` |
| 원격 `main`에 ILA 비교군 디렉터리 존재 | `YES` |
| 원격 `main`에 Custom 계약 파일 7종 존재 | `0/7` |
| Final Demo 브랜치가 `main`에 병합됨 | `NO` |
| Final Demo와 실제 XSA `xparameters.h` 호환 | `FAIL` |
| Final Demo가 실제 BRAM 주소 매크로 인식 | `FAIL` |
| Final Demo 실행 순서: Buffer ARM → Sampler Enable | `FAIL` |
| Final Demo 병합 시 README 충돌 | `YES` |

## 판정

원격 `main`의 CPU Polling, 공통 Generator, Probe Sampler, Trigger Engine 자료는
자동 시험에 통과해 Step 10 참고 자료로 사용할 수 있다. 다만 원격에는
Custom 전체 Routed 계약 파일이 0/7개만
존재하고, 로컬 ILA 비교군 디렉터리도 아직 게시되지 않았다. 따라서 GitHub
파일만으로 Step 9의 Custom 공식 비교 Gate를 열 수 없다.

`origin/agent/publish-final-demo` (`841ec509930e24668c86864c0281031dbd92ab13`)의 Vitis Final Demo는
현재 `main` 병합 상태가 `NOT_MERGED`다.
또한 실제 XSA 기반 주소/Clock 매크로 호환 판정이
`FAIL`이고, Buffer ARM보다 Sampler를
먼저 켜는 순서의 동결 명세 적합성은 `FAIL`다.
이 두 항목을 수정하기 전에는 Final Demo 브랜치를 최종 시연본으로 사용하면
안 된다.
