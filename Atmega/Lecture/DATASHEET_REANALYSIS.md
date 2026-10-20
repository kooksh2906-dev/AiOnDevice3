# ATmega128A GPIO 실습 데이터시트 재분석

## 검토 기준

- 대상 1: `01_GPIO_LEDBar`
- 대상 2: `02_GPIO_Input_TactSwitch`
- 기준 문서: ATmega128A Datasheet, General Digital I/O 및 Port D/G 레지스터 설명
- 목적: 교육 원본의 코딩 스타일은 보존하고, 장치 동작과 다른 설명만 교정하며, 구조 개선은 별도 버전으로 분리

## 1. LED Bar 실습 결론

### 데이터시트와 일치하는 부분

- Port D는 PD0~PD7의 8-bit 양방향 GPIO입니다.
- `DDRD = 0xFF`는 Port D의 8개 핀을 모두 출력으로 설정합니다.
- 출력 모드에서 `PORTD` 비트 1은 High, 비트 0은 Low를 구동합니다.
- `PORTD` 전체에 8-bit 패턴을 기록하는 방식은 LED Bar가 Port D 전체를 독점하는 실습 구성에서 타당합니다.
- 원본 구조체 버전의 `*(led->port - 1)`은 ATmega128A Register Summary에서 데이터 공간 주소가 `PORTD=$32`, `DDRD=$31`(I/O 주소 `$12`, `$11`)로 인접하므로 이 장치에서는 동작합니다.

### 유지해야 할 주의사항

- `port - 1` 방식은 ATmega128A의 레지스터 배치에 의존합니다. 별도 `ddr` 포인터를 저장하는 `VER4_Improved_Explicit_DDR`가 재사용성과 의도 표현 면에서 더 적절합니다.
- LED의 실제 점등 논리는 MCU가 아니라 외부 배선에 의해 결정됩니다. 현재 코드는 High에서 점등되는 Active-High 결선을 전제로 합니다.
- Port D 핀은 T2, T1, USART1, 외부 인터럽트, TWI 등과 겸용됩니다. 해당 주변장치 기능을 활성화하지 않고 GPIO로 사용하는 실습 환경을 전제로 합니다.
- `_delay_ms()`는 Blocking Delay이며, 실제 지연값은 빌드 시 `F_CPU` 설정에 의존합니다.
- Left/Right는 비트 번호 방향입니다. LED Bar의 물리적 좌우는 배선 순서에 따라 반대로 보일 수 있습니다.

### 코드 판정

- VER1~VER3: 핵심 로직 이상 없음
- VER4 원본: ATmega128A에서는 유효하나 장치 종속성 명시 필요
- VER4 개선판: 현재와 같이 명시적 `ddr` 포인터 방식 유지 권장
- VER5 추가 패턴: Shift 범위와 `uint8_t` 변환이 적절하며 교육용 확장으로 타당

## 2. Tact Switch 실습 결론

### 데이터시트와 일치하는 부분

- `DDRGn = 0`은 PGn을 입력으로 설정합니다.
- `PINGn`으로 실제 핀 입력값을 읽는 방식이 맞습니다.
- 외부 Pull-up과 GND 스위치 결선에서는 놓음=High, 누름=Low인 Active-Low 판정이 맞습니다.
- `DDRG &= ~(1 << n)`은 해당 비트만 0으로 만들고 다른 방향 설정을 보존합니다.
- 8-bit Rotate-Left/Right 식은 `uint8_t`에 다시 저장되는 조건에서 의도대로 동작합니다.

### 새로 반영해야 할 조건

- Port G는 5-bit 포트이며 PG0~PG4만 존재합니다.
- PG2는 ALE, PG3/PG4는 TOSC2/TOSC1 겸용 핀이므로 관련 주변기능이 비활성화되어야 버튼 GPIO로 사용할 수 있습니다.
- 입력 모드에서 `PORTGn=1`이면 내부 Pull-up이 켜집니다(`SFIOR.PUD=0` 전제). 외부 Pull-up을 쓰는 개선 모듈은 `PORTGn=0`을 명시해야 합니다.
- Reset 직후 `PORTG=0`, `DDRG=0`이므로 원본 단독 프로그램은 외부 Pull-up 조건에서 정상적인 초기 설정을 가집니다. 다만 재사용 모듈은 Reset 초기값에 의존하지 않는 편이 안전합니다.
- `PING` 판독은 내부 Synchronizer 때문에 짧은 지연이 있지만 사람의 버튼 입력과 50~200 ms 지연 규모에서는 무시할 수 있습니다.

### 원자료 설명 교정

- `DDRG &= ~(1 << 4)`가 DDRG 전체를 `0b00000`으로 만든다는 설명은 일반적으로 틀립니다. Reset 직후 다른 비트가 이미 0인 경우 결과가 우연히 전체 0으로 보일 뿐입니다.
- 버튼을 눌렀을 때는 접점이 닫혀 PG 핀이 GND에 연결됩니다.
- 회로의 Pull-up 저항은 첫 도면의 10 kOhm이 타당하며 후속 도면의 10 Ohm은 오기로 봅니다.
- 지역변수는 반복문마다 다시 초기화되는 것이 아니라 `main()`이 실행되는 동안 값을 유지하고 대입될 때 갱신됩니다.
- VER3의 50 ms 지연은 재샘플링이 없어 완전한 디바운싱이 아닙니다. VER4는 지연 후 핀을 다시 읽어 안정 상태를 확인합니다.

## 최종 판단

- LED Bar 정리본은 현재 버전 구성을 유지하되 데이터시트 기반 주의사항만 보강하면 됩니다.
- Tact Switch는 원형 VER1~VER3를 학습 흐름으로 보존하고, 외부 Pull-up 설정과 재샘플링을 명시한 VER4를 권장 개선판으로 유지합니다.
- 이후 ATmega128A 실습도 먼저 데이터시트에서 핀 겸용 기능, DDR/PORT/PIN 관계, Reset 초기값, Clock 및 Timing 조건을 확인한 뒤 코드를 분석합니다.
