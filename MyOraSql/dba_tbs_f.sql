-- dba_tbs.sql : dba_tables (자주 보는 컬럼만)
set pagesize 1000 linesize 260 trimspool on verify off feedback off
column owner      format a20
column tbs_name  format a30
column tbs_space format a20
column status    format a12
column num_rows  format 999999999999
column blocks    format 999999999999
column last_an   format a19


select owner,
       table_name      tbs_name,
       tablespace_name tbs_space,
       status,
       num_rows,
       blocks,
       to_char(last_analyzed, 'YYYY-MM-DD HH24:MI:SS') last_an
from dba_tables
order by last_an desc nulls last, owner, table_name;

