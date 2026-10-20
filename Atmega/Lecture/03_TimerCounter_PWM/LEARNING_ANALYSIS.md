# Learning Analysis

## 학습 흐름에서 드러나는 성장

1. **Delay 함수에서 하드웨어 시간축으로 확장**
   - `_delay_ms()`로 CPU를 대기시키는 방식에서 Prescaler와 Counter를 이용해 주변장치가 시간을 생성하는 방식으로 확장했습니다.
2. **Flag Polling과 Write-One-to-Clear 이해**
   - `OCF0`, `TOV0`를 폴링하고 해당 비트에 1을 써서 해제하는 ATmega Flag 처리 방식을 학습했습니다.
3. **CTC 하드웨어 출력 이해**
   - CPU가 핀을 직접 반전하지 않아도 Compare Match와 COM 비트 설정으로 OC0가 Toggle되는 흐름을 확인했습니다.
4. **Counter Preload를 이용한 주기 설계**
   - Normal Mode에서 `TCNT0=6`을 Preload하여 Overflow까지 필요한 Count를 250으로 조정했습니다.
5. **8-bit PWM Duty 제어**
   - 고정 TOP 0xFF와 OCR0 비교값의 관계를 이용해 비반전 Fast PWM의 Duty를 변경했습니다.
6. **16-bit PWM 주기와 Pulse Width 분리**
   - Timer1 Mode 14에서 ICR1은 주기, OCR1A는 High Pulse Width를 결정하도록 역할을 분리했습니다.
7. **원형 코드의 경계조건 개선**
   - `uint8_t i < 256`이 종료되지 않는 이유를 타입 범위와 Overflow 관점에서 분석하고 16-bit 반복변수로 수정했습니다.
8. **모듈화와 단위 기반 API 확장**
   - 레지스터 값을 메인 함수에 직접 나열하는 방식에서 PWM 초기화·비교값·마이크로초 Pulse 설정 함수로 발전시켰습니다.

## 이력서·면접에 활용 가능한 근거

- ATmega128A Timer/Counter0·1 레지스터를 직접 설정하여 CTC, Overflow, Fast PWM 동작을 구성한 경험
- Prescaler, TOP, Compare 값으로 출력 주기와 Duty/Pulse Width를 계산하고 코드 설정값과 대조한 경험
- 상태 Flag의 Write-One-to-Clear 특성과 하드웨어 Output Compare 동작을 이해하고 폴링 코드로 확인한 경험
- 8-bit 반복변수의 경계조건 문제를 발견하고 모듈형 개선 코드로 분리한 경험

## 표현 시 주의점

- 현재 백업은 코드·데이터시트 대조와 호스트 문법 검사까지 완료한 상태이며 실물 파형 측정을 완료했다고 설명하면 안 됩니다.
- VER2의 250 Hz는 명령 실행 시간을 제외한 명목 계산값입니다.
- VER6은 Pulse Width 변경 코드이며, 연결 장치가 확인되지 않았으므로 Servo 각도 제어 성공으로 단정하지 않습니다.
- Timer0와 Timer1은 같은 `CS` 비트 조합이라도 분주비 표가 다를 수 있으므로 각각의 데이터시트 표를 기준으로 설명해야 합니다.
