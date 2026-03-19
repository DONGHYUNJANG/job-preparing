-- user_trigs.sql : 트리거 목록 (자주 쓰는 메타만)
set pagesize 1000 linesize 320 trimspool on verify off feedback off
column trig_name  format a35
column tbl_name   format a35
column trig_type  format a20
column status     format a12
column when_clause format a40

accept tr prompt 'TRIGGER_NAME (blank=all): '

select trigger_name trig_name,
       table_name    tbl_name,
       trigger_type  trig_type,
       status,
       substr(when_clause, 1, 40) when_clause
from user_triggers
where ('&tr' = '' or trigger_name = upper('&tr'))
order by status, table_name, trigger_name;

