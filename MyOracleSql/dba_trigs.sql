-- dba_trigs.sql : 트리거 목록 (자주 쓰는 메타만)
set pagesize 1000 linesize 340 trimspool on verify off feedback off
column owner      format a20
column trig_name  format a35
column tbl_name   format a35
column trig_type  format a20
column status     format a12
column when_clause format a45

accept o  prompt 'OWNER (blank=all): '
accept tr prompt 'TRIGGER_NAME (blank=all): '

select owner,
       trigger_name trig_name,
       table_name   tbl_name,
       trigger_type trig_type,
       status,
       substr(when_clause, 1, 45) when_clause
from dba_triggers
where ('&o' = '' or owner = upper('&o'))
  and ('&tr' = '' or trigger_name = upper('&tr'))
order by owner, status, table_name, trigger_name;

