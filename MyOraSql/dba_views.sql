-- dba_views.sql : 뷰 목록 (자주 쓰는 메타만)
set pagesize 1000 linesize 260 trimspool on verify off feedback off
column owner     format a20
column view_name format a35
column status    format a12
column last_ddl  format a19
column created   format a10

accept o prompt 'OWNER (blank=all): '

select owner,
       object_name view_name,
       status,
       to_char(last_ddl_time, 'YYYY-MM-DD HH24:MI:SS') last_ddl,
       to_char(created, 'YYYY-MM-DD') created
from dba_objects
where object_type = 'VIEW'
  and ('&o' = '' or owner = upper('&o'))
order by last_ddl desc nulls last, owner, view_name;
