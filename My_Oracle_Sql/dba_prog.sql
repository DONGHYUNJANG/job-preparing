-- dba_prog.sql : 프로시저/펑션/패키지 목록 (자주 쓰는 메타만)
set pagesize 1000 linesize 280 trimspool on verify off feedback off
column owner    format a20
column type_    format a20
column prog_name format a60
column status   format a12
column last_ddl format a19

accept o prompt 'OWNER (blank=all): '
accept p prompt 'OBJECT_NAME (blank=all): '

select owner,
       object_type type_,
       object_name prog_name,
       status,
       to_char(last_ddl_time, 'YYYY-MM-DD HH24:MI:SS') last_ddl
from dba_objects
where object_type in ('PROCEDURE', 'FUNCTION', 'PACKAGE', 'PACKAGE BODY')
  and ('&o' = '' or owner = upper('&o'))
  and ('&p' = '' or object_name = upper('&p'))
order by owner, type_, last_ddl desc nulls last, prog_name;

