#!/bin/bash

echo "========================================"
echo " 1. 리스너 기동 (lsnrctl start)"
echo "========================================"
lsnrctl start

echo ""
echo "========================================"
echo " 2. Standby DB Mount 및 MRP 시작/점검"
echo "========================================"
sqlplus -s / as sysdba <<EOF

-- 콘솔 출력 화면 넓이 및 컬럼 포맷 조정
SET LINESIZE 200;
SET PAGESIZE 100;
COL process FORMAT A15;
COL status FORMAT A20;
COL open_mode FORMAT A20;
COL database_role FORMAT A20;

-- Mount 상태로 기동
STARTUP MOUNT;

-- MRP 시작 (백그라운드 실행)
RECOVER MANAGED STANDBY DATABASE DISCONNECT;

-- -----------------------------------------
-- 상태 점검 쿼리 모음
-- -----------------------------------------

PROMPT
PROMPT ========================================
PROMPT  [1] MRP 상태 확인 (MRP0 APPLYING_LOG 정상)
PROMPT ========================================
SELECT process, status FROM v\$managed_standby WHERE process LIKE 'MRP%';

PROMPT
PROMPT ========================================
PROMPT  [2] 인스턴스 상태 확인 (MOUNTED 정상)
PROMPT ========================================
SELECT status FROM v\$instance;

PROMPT
PROMPT ========================================
PROMPT  [3] 데이터베이스 Role 확인 (PHYSICAL STANDBY 정상)
PROMPT ========================================
SELECT open_mode, database_role FROM v\$database;

EXIT;
EOF

echo ""
echo "========================================"
echo " Standby 기동 및 점검 스크립트 완료"
echo "========================================"
