# 자율주행 통합 실패·미완성 시도본

STM32 RC카의 개인 개발 과정에서 자율주행 판단, Bluetooth 수동 조종, 모터 PWM 제어 및 CAN 상태 송신을 하나의 FreeRTOS 구조로 통합하려 했던 소스·헤더 파일 보관본입니다.

이 디렉터리는 **성공한 자율주행 구현이나 재현 가능한 최종 펌웨어가 아닙니다.** 별도로 첨부·보관하던 원문 7개 파일을 개발 이력 보존 목적으로 수정 없이 저장했습니다.

## 포함 파일

- `Core/Src/freertos.c`: 초음파 거리 갱신 태스크, 수동·자율 주행 판단, 속도 단계 및 CAN 상태 송신 시도
- `Core/Src/motor.c`, `Core/Inc/motor.h`: L298N 방향 제어와 TIM4 PWM 기반 모터 함수
- `Core/Src/bluetooth.c`, `Core/Inc/bluetooth.h`: UART 인터럽트 수신과 수동·자율 모드 명령
- `Core/Src/ultrasonic.c`, `Core/Inc/ultrasonic.h`: 좌·전방·우측 거리 접근 함수의 미완성 연결 코드

## 확인된 한계

- 자율주행 통합 및 실물 동작에 성공한 완성본이 아닙니다.
- `freertos.c`가 참조하는 `can_status.h` 및 관련 구현이 이 파일 묶음에 없습니다.
- `ultrasonic.c`가 반환하는 `dist_center_val`, `dist_left_val`, `dist_right_val`의 정의와 실제 측정 구현이 포함되지 않았습니다.
- `bluetooth.c`는 USART3를 사용하며, 동작 확인된 개인 F411RE 수동주행 보관본의 USART1 구성과 다릅니다.
- `main.c`, 주변장치 초기화 코드, `.ioc`, 링커 스크립트, Drivers, Middlewares 및 CubeIDE 설정이 없습니다.
- 따라서 현재 파일만으로는 빌드·실행을 재현할 수 없습니다.

## 해석 기준

- 동작 확인된 Bluetooth 수동주행은 `../manual_drive_freertos/`를 기준으로 합니다.
- 동작 확인된 3채널 HC-SR04 거리 측정은 `../ultrasonic_3ch/`를 기준으로 합니다.
- 이 디렉터리는 자율주행 통합을 시도했지만 완성하지 못한 개발 중간 기록으로만 사용합니다.
- 개인 기여를 설명할 때 성공 기능과 미완성 기능을 반드시 구분합니다.
