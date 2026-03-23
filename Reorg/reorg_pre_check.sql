SET TERMOUT OFF;
COLUMN_V_LINE_SIZE_120; 
SET TERMOUT ON;

-- =============================================================================
-- Initial Setup & Column Formatting
-- =============================================================================
SET FEEDBACK OFF;
SET VERIFY OFF;
SET ECHO OFF;
SET LINESIZE 120;
SET PAGESIZE 100;

COLUMN "SIZE_MB"              FORMAT 999,999,990.99
COLUMN "Recommendation"       FORMAT A90 WRAP
COLUMN param_name             FORMAT A30
COLUMN param_value            FORMAT A20
COLUMN param_desc             FORMAT A50 WRAP
COLUMN os_stat_name           FORMAT A25
COLUMN os_stat_value          FORMAT 999,999,999,999,999
COLUMN tablespace_name        FORMAT A30
COLUMN total_mb               FORMAT 999,999,990.99
COLUMN used_mb                FORMAT 999,999,990.99
COLUMN free_mb                FORMAT 999,999,990.99
COLUMN "USED_%"               FORMAT 990.99
COLUMN log_mode               FORMAT A12
COLUMN recovery_dest_name     FORMAT A60 WRAP
COLUMN pga_stat_name          FORMAT A30
COLUMN "VALUE(MB)"            FORMAT 999,999,990
COLUMN "PGA_TARGET(MB)"       FORMAT 999,999,990
COLUMN "CACHE_HIT(%)"         FORMAT 990
COLUMN estd_overalloc_count   FORMAT 999,999,990

PROMPT +------------------------------------------------------------------------+
PROMPT | Oracle Reorganization 사전 점검 스크립트                               |
PROMPT +------------------------------------------------------------------------+

PROMPT 
PROMPT ===[ 1. 대상 스키마 점검 ]================================================
PROMPT
ACCEPT schema_name CHAR PROMPT '점검할 스키마 이름을 입력하세요: ' DEFAULT 'SH'

PROMPT
PROMPT [1-1] 스키마 전체 크기

PROMPT - 스키마(&schema_name)의 전체 디스크 사용량을 계산합니다.
PROMPT 
SELECT
    SUM(bytes) / 1024 / 1024 AS "SIZE_MB"
FROM
    dba_segments
WHERE
    owner = UPPER('&schema_name');

PROMPT
PROMPT [1-2] 재구성(Reorg) 권장 사항

PROMPT - 스키마 크기가 클 경우, 공간 회수 및 성능 향상의 가능성이 있습니다.
PROMPT 
SELECT
    CASE
        WHEN SUM(bytes) > 0 THEN '스키마 ' || UPPER('&schema_name') || '는 재구성 가능합니다. (총 크기: ' || ROUND(SUM(bytes)/1024/1024, 2) || ' MB).'
        ELSE '스키마 ' || UPPER('&schema_name') || '에 데이터가 없으므로 재구성이 필요하지 않습니다.'
    END AS "Recommendation"
FROM
    dba_segments
WHERE
    owner = UPPER('&schema_name');

PROMPT 
PROMPT ===[ 2. CPU 및 병렬 처리 점검 ]============================================
PROMPT
PROMPT [2-1] CPU 코어 및 병렬 처리 파라미터

PROMPT - CPU_COUNT: 인스턴스가 사용 가능한 CPU 코어 수.
PROMPT - PARALLEL_MAX_SERVERS: 최대 병렬 프로세스 수.
PROMPT - 권장 병렬 처리 수준(DOP)은 보통 CPU_COUNT 또는 그 절반입니다.
PROMPT
SELECT 
    name        AS param_name, 
    value       AS param_value, 
    description AS param_desc
FROM 
    v$parameter 
WHERE 
    name IN ('cpu_count', 'parallel_max_servers');

PROMPT
PROMPT [2-2] OS CPU 부하 (Optional)

PROMPT - BUSY_TIME / (BUSY_TIME + IDLE_TIME)으로 현재 CPU 사용률을 계산합니다.
PROMPT - 시스템 부하가 높을 경우 병렬 처리 수준(DOP)을 낮추는 것을 권장합니다.
PROMPT
SELECT 
    stat_name AS os_stat_name, 
    value     AS os_stat_value
FROM 
    v$osstat 
WHERE 
    stat_name IN ('BUSY_TIME', 'IDLE_TIME', 'LOAD');


PROMPT
PROMPT ===[ 3. 시스템 자원 점검 ]================================================
PROMPT
PROMPT [3-1] Undo 테이블스페이스 사용량

PROMPT - 'ALTER TABLE ... MOVE'는 단일 트랜잭션으로 많은 Undo 공간을 사용합니다.
PROMPT - 권장: 최소한 재구성 대상이 되는 가장 큰 테이블의 크기만큼,
PROMPT   안전하게는 스키마 전체 크기만큼의 여유 공간을 확보해야 합니다.
PROMPT
SELECT
    A.tablespace_name,
    A.total_mb,
    NVL(B.used_mb, 0)                 AS used_mb,
    A.total_mb - NVL(B.used_mb, 0)    AS free_mb,
    NVL(B.used_mb, 0) / A.total_mb * 100 AS "USED_%"
FROM
    (SELECT 
        tablespace_name, 
        SUM(bytes) / 1024 / 1024 AS total_mb
     FROM 
        dba_data_files
     WHERE 
        tablespace_name = (SELECT value FROM v$parameter WHERE name = 'undo_tablespace')
     GROUP BY 
        tablespace_name
    ) A,
    (SELECT 
        tablespace_name, 
        SUM(bytes) / 1024 / 1024 AS used_mb
     FROM 
        dba_undo_extents
     WHERE 
        tablespace_name = (SELECT value FROM v$parameter WHERE name = 'undo_tablespace')
        AND status <> 'EXPIRED'
     GROUP BY 
        tablespace_name
    ) B
WHERE
    A.tablespace_name = B.tablespace_name(+);

PROMPT
PROMPT [3-2] Temporary 테이블스페이스 사용량

PROMPT - 인덱스 리빌드 시 정렬(Sort) 연산을 위해 Temp 공간이 대량으로 사용됩니다.
PROMPT - 권장: 최소한 스키마에서 가장 큰 인덱스의 크기만큼의 여유 공간을
PROMPT   확보하는 것이 좋습니다.
PROMPT
SELECT 
    D.tablespace_name,
    NVL(D.total_space, 0) / 1024 / 1024               AS "TOTAL_MB",
    NVL(D.total_space - F.free_space, 0) / 1024 / 1024  AS "USED_MB",
    NVL(F.free_space, 0) / 1024 / 1024                AS "FREE_MB",
    NVL((D.total_space - F.free_space) / D.total_space * 100, 0) AS "USED_%"
FROM   
    (SELECT 
        tablespace_name, 
        SUM(bytes) AS total_space
     FROM   
        dba_temp_files
     GROUP BY 
        tablespace_name
    ) D,
    (SELECT 
        tablespace_name, 
        SUM(bytes_free) AS free_space
     FROM   
        v$temp_space_header
     GROUP BY 
        tablespace_name
    ) F
WHERE  
    D.tablespace_name = F.tablespace_name(+);

PROMPT
PROMPT [3-3] 아카이브 로그 모드 및 사용량

PROMPT - Reorg 작업은 로깅 시 Redo를 대량으로 발생시키며, 이는 아카이브 로그로 기록됩니다.
PROMPT - 권장: 아카이브 목적지(FRA) 사용률이 낮아야 하며, 테이블 이동에 따른
PROMPT   아카이브 로그 증가량(테이블 크기)을 감당할 수 있어야 합니다.
PROMPT
SELECT 
    log_mode 
FROM 
    v$database;

PROMPT
PROMPT - 아카이브 목적지 사용량 (%).
PROMPT
SELECT
    name AS recovery_dest_name,
    ROUND(space_used / space_limit * 100, 2) AS "USED_%"
FROM
    v$recovery_file_dest
WHERE
    space_limit > 0;

PROMPT
PROMPT [3-4] PGA (Program Global Area) 상태
/*
  [ 운영 참고 사항 - 필수 확인 ]
  1. PGA Cache Hit %는 '과거의 통계'입니다. 
     - 현재 100%이더라도, 대규모 Reorg나 Index Rebuild를 '처음' 수행한다면 
       이 수치는 신뢰할 수 없습니다.
  2. Reorg 작업 시 Parallel(병렬) 옵션을 사용할 경우:
     - 각 Parallel Slave가 개별적으로 PGA를 점유하므로 메모리 부족(Temp 사용)이 
       발생할 확률이 급격히 높아집니다.
  3. 대응 방안:
     - 대규모 인덱스 생성 전에는 pga_aggregate_target을 임시로 상향 조정하거나,
     - v$sql_workarea_active를 통해 실시간 'MULTI-PASS(디스크 쓰기)' 발생 여부를 모니터링하세요.
*/
PROMPT - PGA는 인덱스 리빌드 시 정렬과 같은 작업을 메모리 내에서 수행할 때 사용됩니다.
PROMPT - 권장: PGA가 충분하면 디스크(Temp) 대신 메모리에서 빠르게 작업을 처리할 수
PROMPT   있어 성능에 유리합니다. 'PGA Target Advice'의 적중률을 확인하세요.
PROMPT
SELECT 
    name AS pga_stat_name, 
    TRUNC(value / 1024 / 1024) AS "VALUE(MB)" 
FROM 
    v$pgastat 
WHERE 
    name IN (
        'aggregate PGA target parameter', 
        'total PGA allocated', 
        'PGA aggregate limit'
    );

PROMPT
PROMPT - PGA Target Advice를 통한 메모리 요구량 예측
PROMPT
SELECT 
    pga_target_for_estimate / 1024 / 1024   AS "PGA_TARGET(MB)",
    estd_pga_cache_hit_percentage           AS "CACHE_HIT(%)",
    estd_overalloc_count 
FROM 
    v$pga_target_advice;

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | 스크립트 점검 종료                                                     |
PROMPT +------------------------------------------------------------------------+

-- =============================================================================
-- Final Cleanup of SQL*Plus Settings
-- =============================================================================
SET TERMOUT OFF;
COLUMN_V_LINE_SIZE_120;
SET TERMOUT ON;
SET FEEDBACK ON;
SET VERIFY ON;
CLEAR COLUMNS;

