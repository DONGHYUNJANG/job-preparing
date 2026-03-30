#!/bin/bash

echo "========================================"
echo " 1. 데이터베이스 MOUNT 기동 및 Role 확인"
echo "========================================"

# v$ 동적 뷰 충돌 방지를 위해 EOF를 따옴표로 감쌈
lsnrctl start
sqlplus -s / as sysdba <<"EOF"

-- 데이터베이스를 MOUNT 상태로 기동
STARTUP MOUNT;

-- 콘솔 출력 화면 넓이 및 컬럼 포맷 조정
SET LINESIZE 200;
COL name FORMAT A10;
COL open_mode FORMAT A20;
COL database_role FORMAT A20;

PROMPT
PROMPT ========================================
PROMPT  [현재 데이터베이스 역할(Role) 정보]
PROMPT ========================================
SELECT name, open_mode, database_role FROM v$database;

EXIT;
EOF

echo ""
echo "========================================"
echo " 점검이 완료되었습니다. 확인된 Role에 따라 아래 스크립트를 실행하세요."
echo " 반드시 프라이머리를 먼저 시작하시기 바랍니다."
echo "========================================"
echo "프라이머리 스타트 스크립트 \"/home/oracle/start_adg_pri.sh\""
echo "스탠바이 스타트 스크립트 \"/home/oracle/start_sbdb.sh\""
