-- dba_idx.sql : dba_indexes (자주 보는 컬럼만)
set pagesize 1000 linesize 280 trimspool on verify off feedback off
column owner      format a20
column idx_name  format a35
column tbl_name  format a35
column uniq      format a3
column status    format a12
column blevel    format 99999
column leaf_b    format 999999999
column last_an   format a19

accept o prompt 'OWNER (blank=all): '

select owner,
       index_name idx_name,
       table_name tbl_name,
       uniqueness uniq,
       status,
       blevel,
       leaf_blocks leaf_b,
       to_char(last_analyzed, 'YYYY-MM-DD HH24:MI:SS') last_an
from dba_indexes
where ('&o' = '' or owner = upper('&o'))
order by last_an desc nulls last, owner, idx_name;
