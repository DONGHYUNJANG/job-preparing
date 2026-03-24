SET LINESIZE 250
SET PAGESIZE 100
SET VERIFY OFF

COL table_owner FOR a15
COL table_name FOR a20
COL partition_name FOR a20
COL tablespace_name FOR a20
COL high_value FOR a40

SELECT 
    table_owner,
    table_name,
    partition_name,
    partition_position AS pos,
    tablespace_name,
    num_rows,
    blocks,
    high_value
FROM dba_tab_partitions
WHERE table_owner = UPPER('&owner')
  AND table_name  = UPPER('&table_name')
ORDER BY partition_position;