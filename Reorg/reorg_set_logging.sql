SET HEADING OFF;
SET FEEDBACK OFF;
SET VERIFY OFF;
SET TERMOUT ON;
SET LINESIZE 200;

PROMPT 
PROMPT +------------------------------------------------------------------------+
PROMPT | Generating LOGGING script for SH schema...                             |
PROMPT +------------------------------------------------------------------------+
PROMPT 

SPOOL reorg_set_logging_run.sql

-- Generate ALTER TABLE ... LOGGING statements for regular tables
-- Excludes: Partitioned tables, IOTs
SELECT 
    'ALTER TABLE ' || OWNER || '.' || TABLE_NAME || ' LOGGING;'
FROM 
    DBA_TABLES
WHERE 
    OWNER = 'SH'
    AND PARTITIONED = 'NO' -- Exclude partitioned tables
    AND IOT_TYPE IS NULL;   -- Exclude IOTs

SPOOL OFF;

PROMPT 
PROMPT The script 'reorg_set_logging_run.sql' has been generated.
PROMPT Please review it and then run it to apply the changes.
PROMPT 
PROMPT Example execution:
PROMPT @reorg_set_logging_run.sql
PROMPT 

SET HEADING ON;
SET FEEDBACK ON;
SET VERIFY ON;
