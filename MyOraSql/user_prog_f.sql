-- user_prog.sql : 프로시저/펑션/패키지 목록 (자주 쓰는 메타만)
set pagesize 1000 linesize 280 trimspool on verify off feedback off
column type_    format a20
column prog_name format a60
column status   format a12
column last_ddl format a19


select object_type type_,
       object_name  prog_name,
       status,
       to_char(last_ddl_time, 'YYYY-MM-DD HH24:MI:SS') last_ddl
from user_objects
where object_type in ('PROCEDURE', 'FUNCTION', 'PACKAGE', 'PACKAGE BODY')
order by type_, last_ddl desc nulls last, prog_name;

