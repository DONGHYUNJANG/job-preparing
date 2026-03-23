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
PROMPT | Oracle Reorganization Pre-check Script                                 |
PROMPT +------------------------------------------------------------------------+

PROMPT 
PROMPT ===[ 1. Target Schema Check ]=============================================
PROMPT
ACCEPT schema_name CHAR PROMPT 'Enter the schema name to check: ' DEFAULT 'SH'

PROMPT
PROMPT [1-1] Schema Total Size
PROMPT - Calculating total disk space used by schema: &schema_name
PROMPT 
SELECT
    SUM(bytes) / 1024 / 1024 AS "SIZE_MB"
FROM
    dba_segments
WHERE
    owner = UPPER('&schema_name');

PROMPT
PROMPT [1-2] Reorganization Recommendation
PROMPT - A large schema size can indicate potential for space reclamation.
PROMPT 
SELECT
    CASE
        WHEN SUM(bytes) > 0 THEN 'Reorganization is possible for schema ' || UPPER('&schema_name') || ' (' || ROUND(SUM(bytes)/1024/1024, 2) || ' MB).'
        ELSE 'Schema ' || UPPER('&schema_name') || ' has no segments or is empty. Reorganization is not needed.'
    END AS "Recommendation"
FROM
    dba_segments
WHERE
    owner = UPPER('&schema_name');

PROMPT 
PROMPT ===[ 2. CPU and Parallelism Check ]=========================================
PROMPT
PROMPT [2-1] CPU Core and Parallel Parameter
PROMPT - CPU_COUNT: Number of CPU cores available to the instance.
PROMPT - PARALLEL_MAX_SERVERS: Maximum parallel processes.
PROMPT - Recommended DOP (Degree of Parallelism) is usually CPU_COUNT or CPU_COUNT / 2.
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
PROMPT [2-2] OS CPU Load (Optional, requires specific privileges)
PROMPT - BUSY_TIME / (BUSY_TIME + IDLE_TIME) gives the CPU utilization.
PROMPT - A high load average may require reducing the DOP.
PROMPT
SELECT 
    stat_name AS os_stat_name, 
    value     AS os_stat_value
FROM 
    v$osstat 
WHERE 
    stat_name IN ('BUSY_TIME', 'IDLE_TIME', 'LOAD');


PROMPT
PROMPT ===[ 3. Resource Check ]==================================================
PROMPT
PROMPT [3-1] Undo Tablespace Usage
PROMPT - Check the current usage and free space of the Undo tablespace.
PROMPT - Ensure there is enough free space to handle the Reorg transaction.
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
PROMPT [3-2] Temporary Tablespace Usage
PROMPT - Check for sufficient free space in the temporary tablespace.
PROMPT - Large index rebuilds will require significant temp space for sorting.
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
PROMPT [3-3] Archive Log Mode and Usage
PROMPT - LOG_MODE should be 'ARCHIVELOG'.
PROMPT - Check archive destination usage; it must not be full.
PROMPT
SELECT 
    log_mode 
FROM 
    v$database;

PROMPT
PROMPT - Archive destination usage (%).
PROMPT
SELECT
    name AS recovery_dest_name,
    ROUND(space_used / space_limit * 100, 2) AS "USED_%"
FROM
    v$recovery_file_dest
WHERE
    space_limit > 0;

PROMPT
PROMPT [3-4] PGA (Program Global Area) Status
PROMPT - 'total PGA allocated' should be well below 'PGA aggregate limit'.
PROMPT - 'cache hit percentage' on 'PGA Target Advice' should be high (e.g., > 90%).
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
PROMPT - PGA Target Advice to estimate required memory for parallel operations.
PROMPT
SELECT 
    pga_target_for_estimate / 1024 / 1024   AS "PGA_TARGET(MB)",
    estd_pga_cache_hit_percentage           AS "CACHE_HIT(%)",
    estd_overalloc_count 
FROM 
    v$pga_target_advice;

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | End of Pre-check Script                                                |
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
