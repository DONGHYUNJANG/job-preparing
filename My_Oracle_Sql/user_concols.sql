-- user_concols.sql : user_cons_columns (제약조건 컬럼/순서)
set pagesize 1000 linesize 300 trimspool on verify off feedback off
column cons_name format a30
column tbl_name  format a30
column pos       format 99999
column col_name  format a35

accept t prompt 'TABLE_NAME (blank=all): '
accept c prompt 'CONSTRAINT_NAME (blank=all): '

select constraint_name cons_name,
       table_name      tbl_name,
       position        pos,
       column_name     col_name
from user_cons_columns
where ('&t' = '' or table_name = upper('&t'))
  and ('&c' = '' or constraint_name = upper('&c'))
order by cons_name, pos;

