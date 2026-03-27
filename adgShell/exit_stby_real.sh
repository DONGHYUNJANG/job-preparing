#!/bin/bash

# 1. 환경변수 설정 (사용자 환경에 맞게 수정 필요)
# export ORACLE_HOME=/u01/app/oracle/product/19c/dbhome_1
# export ORACLE_SID=ORCL

LOG_FILE="/tmp/stop_mrp_$(date +%Y%m%d_%H%M%S).log"

echo "------------------------------------------" | tee -a $LOG_FILE
echo "시작 시간: $(date)" | tee -a $LOG_FILE
echo "대상 SID: $ORACLE_SID" | tee -a $LOG_FILE
echo "------------------------------------------" | tee -a $LOG_FILE

# 2. SQL*Plus 실행 (EOF를 사용하여 명령어 전달)
sqlplus -s / as sysdba << EOF >> $LOG_FILE 2>&1
SET ECHO ON
SET FEEDBACK ON

-- MRP 중단
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;

-- MRP 상태 확인 (결과가 로그에 기록됨)
SELECT process, status FROM v$managed_standby WHERE process LIKE 'MRP%';

-- DB 종료
SHUTDOWN IMMEDIATE;

EXIT;
EOF

# 3. 종료 결과 확인
if [ $? -eq 0 ]; then
    echo "------------------------------------------"
    echo "SUCCESS: MRP 중단 및 DB 종료 완료."
    echo "로그 확인: $LOG_FILE"
else
    echo "------------------------------------------"
    echo "ERROR: 스크립트 실행 중 문제가 발생했습니다."
    echo "로그를 확인하세요: $LOG_FILE"
fi
