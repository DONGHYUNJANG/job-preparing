-- user_idx.sql : user_indexes (자주 보는 컬럼만)
set pagesize 1000 linesize 260 trimspool on verify off feedback off
column idx_name format a30
column tbl_name format a30
column uniq     format a3
column status   format a12
column blevel   format 99999
column leaf_b   format 999999999
column last_an  format a19


select index_name idx_name,
       table_name tbl_name,
       uniqueness uniq,
       status,
       blevel,
       leaf_blocks leaf_b,
       to_char(last_analyzed, 'YYYY-MM-DD HH24:MI:SS') last_an
from user_indexes
order by last_an desc nulls last, idx_name;

