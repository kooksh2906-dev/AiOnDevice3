# STM32F411RE 개인 펌웨어 프로토타입

STM32 RC카 프로젝트 이전에 STM32F411RE 보드에서 개인적으로 구현·검토한 펌웨어 프로토타입의 보관본입니다. 팀 최종 코드인 상위 `firmware/`와 구분하며, 당시 프로젝트별 `Core/Src`와 `Core/Inc` 원본만 우선 보존합니다.

| 폴더 | 원본 | 확인된 내용 | 상태 |
| --- | --- | --- | --- |
| `manual_drive_freertos` | `LAB_RTOS.zip` | USART1 인터럽트 기반 블루투스 수신, L298N 모터 방향·TIM4 PWM 제어, CMSIS-RTOS v2 `BtTask` 수동 주행 | 사용자 실물 동작 확인 |
| `ultrasonic_3ch` | `LAB_UltraSonicAuto.zip` | TIM3 Input Capture 기반 좌·전방·우측 HC-SR04 거리 측정 | 사용자 실물 동작 확인 |
| `autonomous_drive_attempt_incomplete` | 별도 첨부 소스·헤더 7개 | 거리 기반 자율주행 판단, Bluetooth 수동 모드, 모터 PWM 및 CAN 상태 송신 통합 시도 | 실패·미완성 개발 기록 |

## 자율주행 코드 상태

`manual_drive_freertos/Core/Src/freertos.c`에는 `AutoTask`와 모드 전환의 초기 골격이 있으나, 실제 자율주행 로직 대신 동작 확인용 코드와 초음파 센서 연동 예정 위치만 남아 있습니다. `ultrasonic_3ch`에는 3채널 거리 측정 코드가 존재하지만 모터 제어 및 FreeRTOS 태스크와 통합되어 있지 않습니다.

`autonomous_drive_attempt_incomplete`에는 좌·전방·우측 거리 기반 회피 판단과 수동/자율 모드 전환을 통합하려 한 코드가 있지만, 의존 파일과 센서 측정 구현이 누락되어 있으며 실물 자율주행에 성공한 완성본이 아닙니다.

따라서 이 보관본에서 성공 기능은 Bluetooth 수동 주행과 3채널 거리 측정 프로토타입으로 한정하고, 자율주행 통합 코드는 실패·미완성 시도 기록으로 구분합니다.

## 현재 백업 범위

- 포함: 각 프로젝트의 `Core/Src`, `Core/Inc`, 미완성 시도본 설명 문서
- 미포함: `.ioc`, 링커 스크립트, STM32CubeIDE 프로젝트 설정, `Drivers`, `Middlewares`, Startup 파일
- 제한: 현재 파일만으로는 동일한 빌드 환경이나 실행 이미지를 완전히 재생성할 수 없습니다.

나머지 CubeIDE 프로젝트 구성 파일을 찾으면 각 스냅샷에 원래 디렉터리 구조대로 추가할 예정입니다.
