# 데일리 오라클 서버 헬스 체크 v1.03

파일명: `daily_health_check_v1.03.sh`

이 문서는 `daily_health_check_v1.03.sh` 쉘 스크립트의 기능 및 점검 항목을 요약한 현황표입니다. 스크립트의 실제 점검 순서에 맞춰 정리되었습니다.

| **No.** | **점검 항목** | **상세 설명 및 확인 사항** | 구현 상태 | 비고 |
|:--- |:--- |:--- |:--- |:--- |
| 1 | **OS Disk Usage** | DB 서버 운영체제의 파일 시스템(Mount Point) 잔여 용량 확인 | `[완료]` | `df -h` 명령을 통해 확인 |
| 2 | **Database Status** | 인스턴스(PMON/SMON) 및 데이터베이스가 `OPEN` 상태인지 확인 | `[완료]` | `ps` 명령 및 `V$INSTANCE` 뷰를 통해 확인 |
| 3 | **Tablespace Usage** | 테이블스페이스별 사용률을 확인 (80% 이상 시 WARNING) | `[완료]` | 80% 초과 시 `WARNING` 표시 |
| 4 | **Invalid Objects** | 컴파일 오류 등으로 사용할 수 없는 객체(`INVALID`) 유무 확인 | `[완료]` | `DBA_OBJECTS` 뷰를 통해 확인 |
| 5 | **Unusable Index** | 파티션 작업 등으로 사용할 수 없는 인덱스(`UNUSABLE`) 상태 확인 | `[완료]` | `DBA_INDEXES` 뷰를 통해 확인 |
| 6 | **Datafile Status** | 모든 데이터파일이 `ONLINE` 또는 `SYSTEM` 상태인지 확인 | `[완료]` | `V$DATAFILE` 뷰를 통해 확인 |
| 7 | **Archive & FRA Status** | 아카이브 로그 모드 및 FRA(Fast Recovery Area) 사용량 확인 | `[완료]` | `ARCHIVE LOG LIST`, `V$RECOVERY_FILE_DEST` 뷰를 통해 확인 |
| 8 | **Alert Log ORA Error** | 최근 24시간 이내에 발생한 `ORA-` 에러 로그 모니터링 | `[완료]` | `V$DIAG_ALERT_EXT` 뷰를 통해 확인 |
| 9 | **Blocking Session** | 다른 세션의 작업을 방해하는 블로킹 세션 유무 확인 | `[완료]` | `V$SESSION` 뷰를 통해 확인 |
| 10 | **User Sessions & BG Jobs** | 비정상적으로 오래 실행되는 사용자 세션 및 백그라운드 작업 점검 | `[완료]` | 30분 이상 Active, 3시간 이상 Inactive 세션 확인 |
| 11 | **Redo Log Switch** | 최근 1일간 시간당 로그 스위치 발생 빈도 확인 | `[완료]` | `V$LOG_HISTORY` 뷰를 통해 확인 필요 |
| 12 | **ASM Diskgroup Usage** | ASM 디스크 그룹별 여유 공간 및 상태 점검 | `[완료]` | `V$ASM_DISKGROUP` 뷰를 통해 확인 필요 |
