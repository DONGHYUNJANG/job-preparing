#!/bin/bash

# 1. 환경 변수 설정 (Oracle 사용자로 실행 시 자동으로 가져오도록 개선)
# 시분초까지 포함된 포맷: YYYYMMDD_HHMMSS
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
# 직접 지정이 필요하면 주석을 풀고 경로를 수정하세요.
# export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
# export PATH=$PATH:$ORACLE_HOME/bin

# 리포트 경로 및 파일명 설정
REPORT_DIR="/home/oracle/reports"
mkdir -p $REPORT_DIR
REPORT_FILE="$REPORT_DIR/daily_report_$TIMESTAMP.txt"

# 리포트 초기화
echo "--- Daily Health Check Report ($(date)) ---" > $REPORT_FILE

# 2. 체크할 인스턴스(SID) 목록
INSTANCES=("ORA19")

echo -e "\n[1. Oracle Instance Process (PMON/SMON) Status Check]" >> $REPORT_FILE
# echo 대신 printf를 사용하여 컬럼 정렬을 맞춥니다.
printf "%-15s | %-10s | %-10s | %-10s\n" "INSTANCE_SID" "PMON" "SMON" "STATUS" >> $REPORT_FILE
echo "------------------------------------------------------" >> $REPORT_FILE

for SID in "${INSTANCES[@]}"
do
    export ORACLE_SID=$SID
    
    # pmon/smon 프로세스 확인 (grep -c 로 깔끔하게 숫자만 추출)
    PMON_COUNT=$(ps -ef | grep "ora_pmon_$SID" | grep -v grep | wc -l)
    SMON_COUNT=$(ps -ef | grep "ora_smon_$SID" | grep -v grep | wc -l)

    if [ $PMON_COUNT -gt 0 ] && [ $SMON_COUNT -gt 0 ]; then
        STATUS="RUNNING"
        P_CHECK="OK"
        S_CHECK="OK"
    else
        STATUS="DOWN!!"
        [ $PMON_COUNT -gt 0 ] && P_CHECK="OK" || P_CHECK="MISSING"
        [ $SMON_COUNT -gt 0 ] && S_CHECK="OK" || S_CHECK="MISSING"
    fi

    printf "%-15s | %-10s | %-10s | [%-8s]\n" "$SID" "$P_CHECK" "$S_CHECK" "$STATUS" >> $REPORT_FILE
done

# 2. 인스턴스 상태 확인
echo -e "\n[2. Oracle Database Instance Detail Status Check (SQLPlus)]" >> $REPORT_FILE
printf "%-12s | %-12s | %-15s | %-15s\n" "SID" "INSTANCE" "STATUS" "OPEN_MODE" >> $REPORT_FILE
echo "--------------------------------------------------------------------------" >> $REPORT_FILE
for SID in "${INSTANCES[@]}"
do
    # 해당 SID로 환경변수 설정
    export ORACLE_SID=$SID

    # sqlplus를 통해 상태 조회 (Silent 모드 사용)
    # / as sysdba 권한으로 접속하여 결과만 추출합니다.
    RESULT=$(sqlplus -s / as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT instance_name || ',' || status || ',' || (SELECT open_mode FROM v\$database) FROM v\$instance;
EXIT;
EOF
)

    # 결과값이 비어있지 않은지 확인 (DB가 Down된 경우 결과가 없을 수 있음)
    if [ -z "$RESULT" ]; then
        printf "%-12s | %-12s | %-15s | %-15s\n" "$SID" "DOWN" "N/A" "OFFLINE"
    else
        # 쉼표(,)를 기준으로 데이터 분리
        I_NAME=$(echo $RESULT | cut -d',' -f1)
        I_STATUS=$(echo $RESULT | cut -d',' -f2)
        O_MODE=$(echo $RESULT | cut -d',' -f3)
        
        printf "%-12s | %-12s | %-15s | %-15s\n" "$SID" "$I_NAME" "$I_STATUS" "$O_MODE"  >> $REPORT_FILE
    fi
done


# 3. 디스크 용량 확인
echo -e "\n[1. Disk Usage (OS)]" >> $REPORT_FILE
df -h >> $REPORT_FILE

# 4. Oracle 내부 점검 (SQL*Plus)
# 여러 SID일 경우 루프 안으로 넣어야 하지만, 여기서는 단일 인스턴스 기준으로 정리합니다.
sqlplus -s / as sysdba << EOF >> $REPORT_FILE
SET FEEDBACK OFF
SET PAGESIZE 100
SET LINESIZE 120
SET TRIMSPOOL ON
SET COLSEP ' | '

PROMPT
PROMPT [4. Tablespace Usage]
COLUMN TS_NAME FORMAT a25
COLUMN USED_PCT FORMAT 990.99
COLUMN ALLOC_MB FORMAT 9,999,999
COLUMN USED_MB  FORMAT 9,999,999
COLUMN FREE_MB  FORMAT 9,999,999

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
PROMPT [5. Invalid Objects, Unusable Indexes]
COLUMN OBJECT_NAME FORMAT a40
COLUMN INDEX_NAME FORMAT a40

SELECT 'Invalid Objects Count: ' || COUNT(*) as SUMMARY FROM dba_objects WHERE status = 'INVALID';
SELECT object_type, owner, object_name, status
FROM dba_objects
WHERE status = 'INVALID' AND ROWNUM <= 20;

SELECT 'Unusable Indexes Count: ' || COUNT(*) as SUMMARY FROM dba_indexes WHERE status = 'UNUSABLE';
SELECT owner, index_name, status
FROM dba_indexes
WHERE status = 'UNUSABLE';

EXIT;
EOF

echo -e "\n--- Report Generation Completed: $(date) ---" >> $REPORT_FILE

# 6. Oracle 내부 점검 (SQL*Plus)
sqlplus -s / as sysdba << EOF >> $REPORT_FILE
SET FEEDBACK OFF
SET PAGESIZE 100
SET LINESIZE 120
SET TRIMSPOOL ON
SET COLSEP ' | '
SET DEFINE OFF

PROMPT
PROMPT [6. Datafile Status Check]
-- 헤더를 깔끔하게 만들기 위해 COLUMN 명령어를 사용합니다.
COLUMN SUMMARY FORMAT a40

-- 총 데이터파일 수
SELECT 'Total Datafiles: ' || COUNT(*) AS SUMMARY 
FROM v\$datafile;

-- 상태 이상 파일 수 (결과가 0이어야 정상)
-- 헤더가 지저분하게 나오지 않도록 별칭(AS)을 꼭 줍니다.
SELECT 'Critical Status Files: ' || COUNT(*) AS SUMMARY
FROM v\$datafile 
WHERE status NOT IN ('ONLINE', 'SYSTEM');

-- 만약 이상이 있다면 리스트 출력
SELECT file#, name, status 
FROM v\$datafile 
WHERE status NOT IN ('ONLINE', 'SYSTEM');

EXIT;
EOF

# 7. Archive Mode 및 FRA 사용량 점검
sqlplus -s / as sysdba << EOF >> $REPORT_FILE
SET FEEDBACK OFF
SET PAGESIZE 100
SET LINESIZE 120
SET TRIMSPOOL ON

PROMPT
PROMPT [7. Archive Log Mode, FRA Status]
-- 1) 아카이브 모드 활성화 여부 및 현재 목적지 확인
ARCHIVE LOG LIST;

PROMPT
-- 2) FRA 공간 점검 (기존 7번 내용)
COLUMN NAME FORMAT a30
SELECT NAME,
       SPACE_LIMIT / 1024 / 1024 / 1024 AS LIMIT_GB,
       SPACE_USED / 1024 / 1024 / 1024 AS USED_GB,
       ROUND((SPACE_USED - SPACE_RECLAIMABLE) / SPACE_LIMIT * 100, 2) AS USED_PCT
FROM V\$RECOVERY_FILE_DEST;

EXIT;
EOF

# 8. 최근 24시간 이내 ORA- 에러 로그 점검
sqlplus -s / as sysdba << EOF >> $REPORT_FILE
SET FEEDBACK OFF
SET PAGESIZE 100
SET LINESIZE 150
SET TRIMSPOOL ON
SET COLSEP ' | '

PROMPT
PROMPT [8. ORA- Errors in Last 24 Hours]
COLUMN ORIGINATING_TIMESTAMP FORMAT a30
COLUMN MESSAGE_TEXT FORMAT a100

-- 에러가 없을 경우를 대비해 카운트를 먼저 보여줍니다.
SELECT 'Total ORA- Errors: ' || COUNT(*) AS SUMMARY
FROM V\$DIAG_ALERT_EXT
WHERE COMPONENT_ID = 'rdbms'
  AND MESSAGE_TEXT LIKE '%ORA-%'
  AND ORIGINATING_TIMESTAMP > SYSDATE - 1;

-- 상세 에러 로그 출력 (발생 시각, 메시지 내용)
SELECT ORIGINATING_TIMESTAMP, MESSAGE_TEXT
FROM V\$DIAG_ALERT_EXT
WHERE COMPONENT_ID = 'rdbms'
  AND MESSAGE_TEXT LIKE '%ORA-%'
  AND ORIGINATING_TIMESTAMP > SYSDATE - 1
ORDER BY ORIGINATING_TIMESTAMP DESC;

EXIT;
EOF

# 9. 블로킹 세션(Blocking Session) 유무 및 조치 정보 점검
sqlplus -s / as sysdba << EOF >> $REPORT_FILE
SET FEEDBACK OFF
SET PAGESIZE 100
SET LINESIZE 200      -- 가로 길이를 충분히 확보하여 줄바꿈 방지
SET TRIMSPOOL ON
SET COLSEP '  |  '    -- 구분선을 더 명확하게 설정
SET DEFINE OFF

PROMPT
PROMPT [9. Blocking Session & Kill Command List]
-- 컬럼 너비 최적화 (A 뒤의 숫자가 너비입니다)
COLUMN WAIT_SESS    FORMAT a15 HEADING 'WAIT(SID,SER#)'
COLUMN BLOCK_SESS   FORMAT a15 HEADING 'BLOCK(SID,SER#)'
COLUMN BLOCK_MACH   FORMAT a20 HEADING 'BLOCKER_MACHINE'
COLUMN WAIT_EVENT   FORMAT a30 HEADING 'WAIT_EVENT'
COLUMN W_TIME       FORMAT 999,990 HEADING 'W_SEC'
COLUMN KILL_COMMAND FORMAT a55 HEADING 'KILL_COMMAND_IMMEDIATE'

-- 대기 세션과 블로킹 세션(범인)의 상세 정보 및 Kill 명령어를 생성합니다.
SELECT s.sid || ',' || s.serial# AS WAIT_SESS,
       b.sid || ',' || b.serial# AS BLOCK_SESS,
       b.machine AS BLOCKER_MACHINE,
       s.event AS WAIT_EVENT,
       s.seconds_in_wait AS W_TIME,
       -- 실무에서 바로 복사해서 쓸 수 있는 Kill 구문을 만듭니다.
       'ALTER SYSTEM KILL SESSION ''' || b.sid || ',' || b.serial# || ''' IMMEDIATE;' AS KILL_COMMAND
FROM v\$session s, v\$session b
WHERE s.blocking_session IS NOT NULL
  AND s.blocking_session = b.sid;

-- 결과가 없을 경우
SELECT 'No Blocking Sessions Found' AS STATUS
FROM dual
WHERE NOT EXISTS (SELECT 1 FROM v\$session WHERE blocking_session IS NOT NULL);

EXIT;
EOF
