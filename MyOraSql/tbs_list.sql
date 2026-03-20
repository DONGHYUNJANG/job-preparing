-- tbs_list.sql : DBA_TABLESPACES (테이블스페이스 목록/속성)
set pagesize 1000 linesize 260 trimspool on verify off feedback off
column tablespace_name           format a30
column contents                  format a15
column extent_management         format a20
column segment_space_management  format a30
column status                     format a12
column bigfile                    format a3
column allocation_type           format a15
column def_autoextensible         format a3

select tablespace_name,
       contents,
       extent_management,
       segment_space_management,
       status,
       bigfile,
       allocation_type,
       def_autoextensible
from dba_tablespaces
order by tablespace_name;

