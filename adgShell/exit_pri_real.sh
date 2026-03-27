#!/bin/bash

# 1. 환경변수 로드 (사용자 환경에 맞게 .bash_profile 등을 소싱하거나 직접 설정)
# . /home/oracle/.bash_profile

LOG_FILE="/tmp/stop_primary_$(date +%Y%m%d_%H%M%S).log"

echo "==========================================" | tee -a $LOG_FILE
echo "Primary DB 종료 프로세스 시작: $(date)" | tee -a $LOG_FILE
echo "대상 SID: $ORACLE_SID" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE

# 2. 리스너 중단 (새로운 세션 접속 차단)
echo "Stopping Listener..." | tee -a $LOG_FILE
lsnrctl stop >> $LOG_FILE 2>&1

# 3. SQL*Plus 접속 및 DB 종료
echo "Shutting down Database (IMMEDIATE)..." | tee -a $LOG_FILE
sqlplus -s / as sysdba << EOF >> $LOG_FILE 2>&1
SET ECHO ON
SET FEEDBACK ON

-- 마지막 아카이브 로그 전송 (권장)
alter system archive log current;

-- 현재 오픈된 세션 확인 (로그 기록용)
SELECT count(*) FROM v\$session WHERE type = 'USER';

-- DB 정상 종료
SHUTDOWN IMMEDIATE;

EXIT;
EOF

# 4. 종료 결과 확인
if [ $? -eq 0 ]; then
    echo "------------------------------------------"
    echo "SUCCESS: 리스너 및 Primary DB 종료 완료."
    echo "로그 확인: $LOG_FILE"
else
    echo "------------------------------------------"
    echo "ERROR: 종료 중 오류가 발생했습니다. 로그를 확인하세요."
    echo "로그 확인: $LOG_FILE"
fi
