# Step 10 팀 인수인계

## 지금 전달 가능한 것

- ILA 보드 시험 4종 PASS 증거
- 정규화 CSV 3종과 검증 보고서
- Pulse Stress 60/60 원본·정규화·ILA Session Checksum
- Common / CPU / ILA 전체 Routed 자원·Timing 표
- 발표용 SVG 2개와 안전한 발표 문안
- GitHub 원격 Commit `c41254682dee66bbb5cea763641ba20aebd94e58` 감사 결과

## 최종 완료에 필요한 팀 입력

`comparison/ila_reference/results/step9/inputs/custom/`에 같은 Implementation
Run에서 생성한 다음 7개 파일을 넣는다.

1. `utilization.rpt`
2. `hierarchical_utilization.rpt`
3. `timing_summary.rpt`
4. `route_status.rpt`
5. `drc.rpt`
6. `routed_design.dcp`
7. `build_manifest.rpt`

## 최종 승격 명령

```bash
comparison/ila_reference/run_step9_resource_timing.sh --strict-complete
comparison/ila_reference/run_step10_final_package.sh
```

첫 명령이 `NEXT_ACTION=STEP10_FINAL_PACKAGE`를 만들지 못하면 두 번째 명령은
Final 패키지를 생성하지 않는다. 임시 발표자료가 다시 필요할 때만
`--draft`를 사용한다.

## GitHub 게시 전 확인

- [ ] 로컬 `comparison/ila_reference/` 전체를 검토해 의도한 파일만 Stage
- [ ] Build Cache와 중복 Hardware Log 제외
- [ ] Step 6~10 `SHA256SUMS` 재검증
- [ ] 원격 `main` 최신 Commit과 충돌 확인
- [ ] `agent/publish-final-demo` 병합 여부를 팀에서 결정
- [ ] Final Demo의 Sampler/Trigger/Timer/BRAM 실제 XSA 매크로 Alias 수정
- [ ] Final Demo 순서를 `capture_arm()` → `sampler_enable()`로 교정
- [ ] Trigger TB 실패/Timeout을 `$fatal(1, ...)`로 변경
- [ ] 기본 회귀에 Sampler/Trigger TB 추가
- [ ] README 병합 충돌 해결 시 CPU Polling과 Final Demo 섹션 모두 보존
- [ ] Custom 공식 수치가 `PENDING_CUSTOM`이면 Draft Badge 유지
