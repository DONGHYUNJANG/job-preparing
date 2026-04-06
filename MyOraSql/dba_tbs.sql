-- dba_tbs.sql : dba_tables (자주 보는 컬럼만)
set pagesize 1000 linesize 320 trimspool on verify off feedback off
column owner      format a18
column tbs_name  format a28
column tbs_space format a18
column status    format a12
column partitioned format a4
column iot_type    format a14
column num_rows  format 999999999999
column blocks    format 999999999999
column last_an   format a19

accept o prompt 'OWNER (blank=all): '

select owner,
       table_name      tbs_name,
       tablespace_name tbs_space,
       status,
       partitioned,
       iot_type,
       num_rows,
       blocks,
       to_char(last_analyzed, 'YYYY-MM-DD HH24:MI:SS') last_an
from dba_tables
where ('&o' = '' or owner = upper('&o'))
order by last_an desc nulls last, owner, table_name;
