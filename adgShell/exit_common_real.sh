#!/bin/bash

echo "========================================"
echo " 1. 현재 데이터베이스 Role 확인 (종료 전)"
echo "========================================"

# v$ 동적 뷰 충돌 방지를 위해 EOF를 따옴표로 감쌈
sqlplus -s / as sysdba <<"EOF"

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
echo "======================================================"
echo " 🚨 [경고] 데이터베이스 종료 순서 가이드 🚨"
echo "======================================================"
echo " Data Guard 환경에서는 데이터 동기화 오류 방지를 위해"
echo " 반드시 [스탠바이(Standby)]를 먼저 종료하신 후,"
echo " [프라이머리(Primary)]를 종료하시기 바랍니다."
echo "======================================================"
echo ""
echo " 확인된 Role에 따라 아래 스크립트를 복사하여 실행하세요."
echo " ----------------------------------------------------"
echo " 프라이머리 종료 스크립트 : \"/home/oracle/exit_pri_real.sh\""
echo " 스탠바이 종료 스크립트   : \"/home/oracle/exit_stby_real.sh\""
echo " ----------------------------------------------------"
