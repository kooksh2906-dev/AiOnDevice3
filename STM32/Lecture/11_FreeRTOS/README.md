# FreeRTOS

STM32F411RE에서 FreeRTOS 태스크들이 하나의 전역 공유변수에 접근할 때 발생할 수 있는 경쟁 조건과 동기화 방법을 비교한 학습 기록입니다.

## 학습 항목

1. `01_Shared_Variable_Synchronization`
   - 보호 장치가 없는 상태
   - Mutex 적용
   - Semaphore 적용
   - 임계영역 최소화 개선본

실제 제출·실행 자료는 원문 보존본으로 분리하고, 세 방식의 비교를 위해 CubeMX 생성 형식에 맞춘 복원본을 별도로 구성했습니다.
