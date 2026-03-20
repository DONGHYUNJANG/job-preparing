SET TERMOUT OFF;
COLUMN_V_LINE_SIZE_120;
SET TERMOUT ON;

SET FEEDBACK OFF;
SET VERIFY OFF;
SET ECHO OFF;
SET LINESIZE 120;
SET PAGESIZE 100;

PROMPT 
PROMPT +------------------------------------------------------------------------+
PROMPT | Reorg Pre-check Script                                                 |
PROMPT +------------------------------------------------------------------------+
PROMPT 

PROMPT ===[ 1. CPU & Parallelism Check ]=========================================
PROMPT
PROMPT [1-1] CPU Core & Parallel Parameter
PROMPT - CPU_COUNT: Number of CPU cores available to the instance.
PROMPT - PARALLEL_MAX_SERVERS: Maximum parallel processes.
PROMPT - Recommended DOP (Degree of Parallelism) is usually CPU_COUNT or CPU_COUNT / 2.
SELECT 
    NAME, 
    VALUE, 
    DESCRIPTION 
FROM 
    V$PARAMETER 
WHERE 
    NAME IN ('cpu_count', 'parallel_max_servers');

PROMPT
PROMPT [1-2] OS CPU Load (Optional, requires specific privileges)
PROMPT - BUSY_TIME / (BUSY_TIME + IDLE_TIME) gives the CPU utilization.
PROMPT - A high load average may require reducing the DOP.
SELECT 
    STAT_NAME, 
    VALUE 
FROM 
    V$OSSTAT 
WHERE 
    STAT_NAME IN ('BUSY_TIME', 'IDLE_TIME', 'LOAD');


PROMPT
PROMPT ===[ 2. Resource Check ]==================================================
PROMPT
PROMPT [2-1] Undo Tablespace Usage
PROMPT - Check the current usage and free space of the Undo tablespace.
PROMPT - Ensure there is enough free space to handle the Reorg transaction.
SELECT
    A.TABLESPACE_NAME,
    ROUND(A.TOTAL_MB, 2) AS TOTAL_MB,
    ROUND(NVL(B.USED_MB, 0), 2) AS USED_MB,
    ROUND(A.TOTAL_MB - NVL(B.USED_MB, 0), 2) AS FREE_MB,
    ROUND(NVL(B.USED_MB, 0) / A.TOTAL_MB * 100, 2) AS "USED_%"
FROM
    (SELECT TABLESPACE_NAME, SUM(BYTES) / 1024 / 1024 AS TOTAL_MB
     FROM DBA_DATA_FILES
     WHERE TABLESPACE_NAME = (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'undo_tablespace')
     GROUP BY TABLESPACE_NAME) A,
    (SELECT TABLESPACE_NAME, SUM(BYTES) / 1024 / 1024 AS USED_MB
     FROM DBA_UNDO_EXTENTS
     WHERE TABLESPACE_NAME = (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'undo_tablespace')
     AND STATUS <> 'EXPIRED'
     GROUP BY TABLESPACE_NAME) B
WHERE
    A.TABLESPACE_NAME = B.TABLESPACE_NAME(+);

PROMPT
PROMPT [2-2] Temporary Tablespace Usage
PROMPT - Check for sufficient free space in the temporary tablespace.
PROMPT - Large index rebuilds will require significant temp space for sorting.
SELECT D.tablespace_name,
       ROUND(NVL(total_space, 0) / 1024 / 1024, 2) AS "TOTAL_MB",
       ROUND(NVL(total_space - free_space, 0) / 1024 / 1024, 2) AS "USED_MB",
       ROUND(NVL(free_space, 0) / 1024 / 1024, 2) AS "FREE_MB",
       ROUND(NVL((total_space - free_space) / total_space * 100, 0), 2) AS "USED_%"
FROM   (SELECT tablespace_name, SUM(bytes) AS total_space
        FROM   dba_temp_files
        GROUP BY tablespace_name) D,
       (SELECT tablespace_name, SUM(bytes_free) AS free_space
        FROM   v$temp_space_header
        GROUP BY tablespace_name) F
WHERE  D.tablespace_name = F.tablespace_name(+);

PROMPT
PROMPT [2-3] Archive Log Mode & Usage
PROMPT - LOG_MODE should be 'ARCHIVELOG'.
PROMPT - Check archive destination usage; it must not be full.
SELECT 
    LOG_MODE 
FROM 
    V$DATABASE;

PROMPT
PROMPT - Archive destination usage (%).
SELECT
    DEST_NAME,
    ROUND(SPACE_USED / SPACE_LIMIT * 100, 2) AS "USED_%"
FROM
    V$RECOVERY_FILE_DEST
WHERE
    SPACE_LIMIT > 0;

PROMPT
PROMPT [2-4] PGA (Program Global Area) Status
PROMPT - 'total PGA allocated' should be well below 'PGA aggregate limit'.
PROMPT - 'cache hit percentage' on 'PGA Target Advice' should be high (e.g., > 90%).
SELECT 
    NAME, 
    TRUNC(VALUE / 1024 / 1024) AS "VALUE(MB)" 
FROM 
    V$PGASTAT 
WHERE 
    NAME IN (
        'aggregate PGA target parameter', 
        'total PGA allocated', 
        'PGA aggregate limit'
    );

PROMPT
PROMPT - PGA Target Advice to estimate required memory for parallel operations.
SELECT 
    PGA_TARGET_FOR_ESTIMATE / 1024 / 1024 AS "PGA_TARGET(MB)",
    ESTD_PGA_CACHE_HIT_PERCENTAGE AS "CACHE_HIT(%)",
    ESTD_OVERALLOC_COUNT 
FROM 
    V$PGA_TARGET_ADVICE;


PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | End of Pre-check Script                                                |
PROMPT +------------------------------------------------------------------------+
PROMPT 

SET TERMOUT OFF;
COLUMN_V_LINE_SIZE_120;
SET TERMOUT ON;
SET FEEDBACK ON;
SET VERIFY ON;
