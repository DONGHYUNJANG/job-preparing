-- tbs_free_space.sql : DBA_FREE_SPACE (테이블스페이스 프리 블록 상세)
set pagesize 1000 linesize 260 trimspool on verify off feedback off
column tablespace_name format a30
column file_id          format 99999
column block_id         format 99999999999
column blocks           format 999999999
column free_mb          format 999,999,999,990.99

select tablespace_name,
       file_id,
       block_id,
       blocks,
       round(blocks * (select value from v$parameter where name = 'db_block_size') / 1024 / 1024, 2) free_mb
from dba_free_space
order by tablespace_name, file_id, block_id;

