-- generate_lob_reorg_sql.sql
--
-- Description:
--   Generates the SQL commands required to reorganize LOB segments and rebuild LOB indexes
--   for a specific schema. The generated commands are spooled to a file named
--   '_generated_lob_reorg_commands.sql'.
--
-- Parameters:
--   &1: The name of the schema to be reorganized (e.g., 'SH').
--
-- Usage:
--   sqlplus user/pass @generate_lob_reorg_sql.sql <SCHEMA_NAME>
--

SET SERVEROUTPUT ON
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING OFF
SET TERMOUT OFF
SET VERIFY OFF

-- Spool file to save the generated commands
SPOOL _generated_lob_reorg_commands.sql

DECLARE
  SCHEMA_NAME VARCHAR2(30) := UPPER('&1');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- Generated on ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('-- Schema: ' || SCHEMA_NAME);
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------');
END;
/


-- 1. Generate LOB segment reorganization commands
PROMPT -- 1. Generating LOB Reorganization Commands...
SELECT
    'PROMPT "Reorganizing LOB for ' || l.table_name || ' (' || l.column_name || ')...";' || CHR(10) ||
    'ALTER TABLE ' || l.owner || '.' || l.table_name || ' MOVE LOB(' || l.column_name || ') STORE AS (TABLESPACE ' || l.tablespace_name || ');'
FROM
    dba_lobs l
WHERE
    l.owner = UPPER('&1')
    AND l.table_name NOT LIKE 'DR$%'
    AND l.table_name NOT LIKE 'SYS_IOT_OVER_%';

-- 2. Generate LOB index rebuild commands
PROMPT
PROMPT -- 2. Generating LOB Index Rebuild Commands...
SELECT
    'PROMPT "Rebuilding LOB Index ' || i.index_name || '...";' || CHR(10) ||
    'ALTER INDEX ' || i.owner || '.' || i.index_name || ' REBUILD;'
FROM
    dba_indexes i
JOIN
    dba_lobs l ON i.owner = l.owner AND i.index_name = l.index_name
WHERE
    i.index_type = 'LOB'
    AND i.owner = UPPER('&1')
    AND l.table_name NOT LIKE 'DR$%'
    AND l.table_name NOT LIKE 'SYS_IOT_OVER_%';

PROMPT
PROMPT -- Generation Complete.
PROMPT ----------------------------------------------------
PROMPT

SPOOL OFF
SET FEEDBACK ON
SET HEADING ON
SET TERMOUT ON

EXIT;
