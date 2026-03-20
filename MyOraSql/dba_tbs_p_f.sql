-- dba_tbs_p.sql : dba_tab_partitions (파티션만, 자주 보는 컬럼만)
set pagesize 1000 linesize 360 trimspool on verify off feedback off
column owner     format a20
column tbl_name  format a30
column part_name format a30
column part_pos  format 99999
column tbs_space format a20
column status    format a12
column num_rows  format 999999999999
column blocks    format 999999999999
column last_an   format a19
column hi_v      format a60


select owner,
       table_name       tbl_name,
       partition_name   part_name,
       partition_position part_pos,
       tablespace_name  tbs_space,
       status,
       num_rows,
       blocks,
       to_char(last_analyzed, 'YYYY-MM-DD HH24:MI:SS') last_an,
       substr(high_value, 1, 200) hi_v
from dba_tab_partitions
order by owner, table_name, partition_position;

