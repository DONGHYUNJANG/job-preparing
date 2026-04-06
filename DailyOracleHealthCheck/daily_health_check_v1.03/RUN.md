# 데일리 헬스 체크 스크립트 분석 및 작업 계획서

## 1. 구현 현황 점검
README.md의 점검 항목과 daily_health_check_v1.03.sh를 비교 분석한 결과입니다.

| 점검 항목 | 구현 여부 | 비고 |
| --- | --- | --- |
| Database Status | 🟢 구현됨 | PMON/SMON 및 OPEN_MODE 확인 |
| Tablespace Usage | 🟡 부분 구현 | 전체 현황은 출력하나 80% 이상 임계치 강조 기능 부재 |
| Datafile 상태 | 🟢 구현됨 | V$DATAFILE 상태 조회 완료 |
| FRA Usage | 🟢 구현됨 | V$RECOVERY_FILE_DEST 조회 완료 |
| Archive Log Mode/상태 | 🟢 구현됨 | ARCHIVE LOG LIST 수행 완료 |
| Alert Log ORA 에러 | 🟢 구현됨 | V$DIAG_ALERT_EXT에서 최근 24시간 에러 조회 완료 |
| Top Wait Event | ⚪ 제외됨 | 1일 단위 통계의 정확한 구현이 복잡하여 구현 항목에서 제외 |
| Blocking Session | 🟢 구현됨 | V$SESSION, V$SESSION 조인으로 조회 완료 |
| Long Running Session | 🟢 구현됨 | 30분 이상 Active, 3시간 이상 Inactive 세션 조회 완료 |
| Redo 시퀀스/스위치 | 🔴 미구현 | 관련 쿼리 없음 |
| Invalid Objects | 🟢 구현됨 | DBA_OBJECTS 상태 조회 완료 |
| Unusable Index | 🟢 구현됨 | DBA_INDEXES 상태 조회 완료 |
| ASM Diskgroup Usage | 🔴 미구현 | 관련 쿼리 없음 |
| OS Disk Usage | 🟢 구현됨 | df -h 명령어로 조회 완료 |

## 2. 미구현 및 부분 구현 기능에 대한 작업 계획서

### 2.1. Tablespace Usage (부분 구현 개선)
- **목표:** 80% 이상 사용 중인 테이블스페이스를 시각적으로 강조.
- **구현 방법:** 기존 [4. Tablespace Usage] 쿼리를 수정하여, USED_PCT가 80% 이상인 경우 WARNING 등의 상태 메시지를 표시하는 CASE 구문 추가.

### 2.2. Redo Log Switch (미구현)
- **목표:** 로그 스위치 빈도 확인 (시간당 2~4회 적정).
- **구현 방법:**  뷰를 조회하여 최근 1일(또는 지정 기간) 동안의 시간대별 로그 스위치 발생 횟수 추이를 집계하여 출력하는 SQL 추가.

### 2.3. ASM Diskgroup Usage (미구현)
- **목표:** ASM 사용 시 디스크 그룹별 여유 공간 및 상태 점검.
- **구현 방법:**  뷰를 활용하여 디스크 그룹의 총 용량 대비 사용률 및 상태 정보를 출력하는 SQL 추가 (ASM 환경이 아닐 경우 빈 결과 반환).

---
**알림:** 사용자의 지시에 따라, 위 계획은 사용자의 확인 및 별도 지시가 있을 때까지 스크립트에 반영(실행)하지 않으며, 기존에 구현된 코드는 수정하지 않도록 보존합니다.
