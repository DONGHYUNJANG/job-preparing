#!/bin/bash

echo "========================================"
echo " 1. 리스너 기동 (lsnrctl start)"
echo "========================================"
lsnrctl start

echo ""
echo "========================================"
echo " 2. DB Startup 및 상태 점검"
echo "========================================"
sqlplus -s / as sysdba <<EOF

-- DB 기동
alter database open;

-- 콘솔 출력 화면 넓이 조정
SET LINESIZE 200;

-- 정상 확인 (v$ 기호 이스케이프 처리)
SELECT instance_name, status FROM v\$instance;

-- Redo 전송 상태 확인 (v$ 기호 이스케이프 처리)
SELECT dest_id, status, target
FROM v\$archive_dest
WHERE target = 'STANDBY';

EXIT;
EOF

echo "========================================"
echo " 점검 완료"
echo "========================================"
