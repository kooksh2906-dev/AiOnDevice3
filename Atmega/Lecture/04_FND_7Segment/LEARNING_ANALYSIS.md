# Learning Analysis

## 학습 흐름에서 드러나는 성장

1. **8-bit Pattern과 물리 Segment 연결**
   - 각 PORTC bit를 A~G·DP Segment에 대응시키고 숫자 모양을 8-bit 값으로 표현했습니다.
2. **Lookup Table 기반 출력**
   - 여러 Segment 조건문 대신 숫자별 Pattern 배열을 Index로 조회해 출력 로직을 단순화했습니다.
3. **Modulo를 이용한 반복 Index**
   - `count % 10`으로 배열 Index를 0~9 범위로 제한하는 방식을 학습했습니다.
4. **자료형 범위 문제 인식**
   - 장시간 증가하는 Signed `int` 카운터의 Overflow 가능성을 확인하고 명시적인 8-bit 순환 상태로 개선했습니다.
5. **기능 단위 함수 분리**
   - 초기화, 숫자 출력, Clear, 증가·감소 Count를 함수로 분리했습니다.
6. **하드웨어 차이를 소프트웨어 설정으로 흡수**
   - Common Cathode/Anode 극성과 숫자 글꼴 차이를 구조체 설정과 Pattern 변환으로 처리했습니다.
7. **모듈화와 재사용성 향상**
   - DDR·PORT 주소와 표시 설정을 구조체에 묶고 `fnd.c/.h`로 분리했습니다.
8. **4자리 숫자 분리**
   - 0~9999 값을 나눗셈과 나머지 연산으로 1·10·100·1000의 자리 배열에 분리했습니다.
9. **동적 Multiplexing**
   - 하나의 Segment Bus를 공유하면서 자리 선택 신호만 빠르게 바꿔 네 자리가 동시에 보이도록 구성했습니다.
10. **표시 Refresh와 값 갱신 주기 분리**
   - 1 ms 자리 Scan은 계속 유지하고 별도 Frame Counter로 숫자 증가 속도를 제어했습니다.

## 이력서·면접에 활용 가능한 근거

- ATmega128A GPIO 레지스터에 8-bit Segment Pattern을 직접 기록해 1자리 FND를 제어한 경험
- 숫자 Pattern을 Lookup Table로 관리하고 Index 순환과 함수화를 적용한 경험
- 자료형 범위와 장시간 실행 시 Overflow 가능성을 분석해 명시적인 상태 순환으로 개선한 경험
- FND 공통단 극성과 표시 글꼴 차이를 설정 가능한 드라이버 구조로 분리한 경험
- 4자리 값을 자리별로 분리하고 1 ms 단위 Multiplex Scan으로 표시하는 GPIO 제어 구조를 구현한 경험
- 표시 Refresh 주기와 Application Count 주기를 분리해 시간축이 다른 동작을 하나의 Polling Loop에서 관리한 경험

## 표현 시 주의점

- VER1~VER4는 1자리 FND 정적 출력이고 VER5만 4자리 Multiplexing 학습용 구현입니다.
- Common Cathode/Anode 실물 배선은 확인되지 않았으므로 원형 Pattern이 Active-High라는 코드 근거를 중심으로 설명합니다.
- VER5의 Port A 자리 선택 Mapping은 실물 교육보드 배선 복원이 아닌 변경 가능한 예시 구성입니다.
- AVR-GCC 및 실물 보드 검증 전에는 실제 4자리 FND 점등 완료라고 표현하지 않습니다.
