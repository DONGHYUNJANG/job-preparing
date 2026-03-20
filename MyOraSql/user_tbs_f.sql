-- user_tbs.sql : user_tables (자주 보는 컬럼만)
set pagesize 1000 linesize 300 trimspool on verify off feedback off
column tbs_name  format a30
column tbs_space format a20
column status    format a12
column partitioned format a4
column iot_type    format a14
column pct_free  format 999
column pct_used  format 999
column num_rows  format 999999999999
column blocks    format 999999999999
column last_an   format a19


select table_name tbs_name,
       tablespace_name tbs_space,
       status,
       partitioned,
       iot_type,
       pct_free,
       pct_used,
       num_rows,
       blocks,
       to_char(last_analyzed, 'YYYY-MM-DD HH24:MI:SS') last_an
from user_tables
order by last_an desc nulls last, table_name;

