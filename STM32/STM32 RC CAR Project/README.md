# STM32 RC카 프로젝트

온디바이스 반도체 설계 과정의 RC카 팀 프로젝트 코드와 STM32F411RE 개인 프로토타입을 구분하여 정리한 보관본입니다. 차량 구동부와 상태 표시부는 별도의 STM32 펌웨어로 나뉩니다.

| 펌웨어 | 역할 | 주요 코드 |
| --- | --- | --- |
| `firmware/CAN_BUS` | 블루투스 명령 수신, 모터 제어, 초음파 센서 기반 자율 주행, CAN 차량 상태 송신 | `Core/Src/bluetooth_control.c`, `motor_control.c`, `ultrasonic.c`, `autonomous_drive.c`, `can_app.c` |
| `firmware/CAN_LCD_RC` | CAN 차량 상태 수신 및 I2C LCD 표시 | `Core/Src/can_app.c`, `lcd_status.c`, `lcd_i2c.c` |
| `firmware_prototype_f411re/manual_drive_freertos` | F411RE 기반 블루투스 수동 주행 및 FreeRTOS 이식 프로토타입 | `Core/Src/bluetooth.c`, `driving.c`, `motor.c`, `freertos.c` |
| `firmware_prototype_f411re/ultrasonic_3ch` | F411RE 기반 좌·전방·우측 HC-SR04 거리 측정 프로토타입 | `Core/Src/ultrasonic.c`, `main.c` |

## 데이터 흐름

`CAN_BUS`: 블루투스 입력·초음파 측정 → 모터 제어 → CAN 상태 프레임 송신

`CAN_LCD_RC`: CAN 상태 프레임 수신 → 수신 여부·시간 확인 → LCD 두 줄 표시

두 펌웨어의 `Core/Inc/can_protocol.h`는 같은 프레임 정의를 사용합니다. 표준 CAN ID는 `0x101`, 데이터 길이는 4바이트이며 속도(%), 주행 방향, 전방 거리, 생존 카운터 순서로 전송합니다.

## 코드 구성

각 펌웨어의 `Core/Src/freertos.c`는 태스크를 생성하고, 구동부에서는 모터 명령 큐도 생성합니다. 실제 동작은 각 기능별 소스 파일에서 처리합니다. `Drivers/`와 `Middlewares/`에는 STM32 HAL, CMSIS, FreeRTOS 코드가 포함되어 있습니다.

`firmware_prototype_f411re`는 팀 최종 코드와 구분한 개인 F411RE 학습·구현 자료입니다. 블루투스 수동 주행과 3채널 거리 측정은 실물 동작을 확인했으며, 자율주행은 통합에 성공하지 못한 시도 단계로 기록합니다.

현재 저장소의 팀 펌웨어에는 C/H 소스와 라이브러리만 있으며 STM32CubeIDE 프로젝트 파일, `.ioc`, 링커 설정은 포함되어 있지 않습니다. F411RE 프로토타입도 현재 `Core/Src`와 `Core/Inc`만 보관하므로, 이 파일들만으로는 빌드나 펌웨어 재생성이 완료되지 않습니다.
