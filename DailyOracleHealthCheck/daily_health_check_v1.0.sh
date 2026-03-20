#!/bin/bash

# 환경 변수 설정
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
export ORACLE_SID=ora12
export PATH=$PATH:$ORACLE_HOME/bin

REPORT_FILE="/home/oracle/reports/daily_report_$(date +%Y%m%d).txt"

echo "--- Daily Health Check Report ($(date)) ---" > $REPORT_FILE

# 1. 디스크 용량 확인
echo -e "\n[1. Disk Usage (OS)]" >> $REPORT_FILE
df -h >> $REPORT_FILE

# 2. Oracle 내부 점검
sqlplus -s / as sysdba << EOF >> $REPORT_FILE
SET FEEDBACK OFF
SET PAGESIZE 100
SET LINESIZE 150
SET TRIMSPOOL ON

PROMPT
PROMPT [2. Tablespace Usage]
COLUMN TS_NAME FORMAT a20
COLUMN ALLOC_MB FORMAT 9,999,999

SELECT d.tablespace_name AS TS_NAME,
       ROUND(d.total_bytes / 1024 / 1024, 2) AS ALLOC_MB,
       ROUND((d.total_bytes - NVL(f.free_bytes, 0)) / 1024 / 1024, 2) AS USED_MB,
       ROUND(NVL(f.free_bytes, 0) / 1024 / 1024, 2) AS FREE_MB,
       ROUND((d.total_bytes - NVL(f.free_bytes, 0)) / d.total_bytes * 100, 2) AS USED_PCT
FROM (
        SELECT tablespace_name, SUM(bytes) AS total_bytes
        FROM dba_data_files
        GROUP BY tablespace_name
     ) d,
     (
        SELECT tablespace_name, SUM(bytes) AS free_bytes
        FROM dba_free_space
        GROUP BY tablespace_name
     ) f
WHERE d.tablespace_name = f.tablespace_name(+)
ORDER BY USED_PCT DESC;

PROMPT
PROMPT [3. Invalid Objects & Unusable Indexes]
-- 결과가 없을 때도 헤더 출력

SELECT 'Invalid Objects: ' || COUNT(*) FROM dba_objects WHERE status = 'INVALID';
SELECT object_type, object_name, status
FROM dba_objects
WHERE status = 'INVALID';

SELECT 'Unusable Indexes: ' || COUNT(*) FROM dba_indexes WHERE status = 'UNUSABLE';
SELECT index_name, status
FROM dba_indexes
WHERE status = 'UNUSABLE';

EXIT;
EOF

echo -e "\n--- Report Generation Completed ---" >> $REPORT_FILE
