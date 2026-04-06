-- dba_concols.sql : dba_cons_columns (제약조건 컬럼/순서)
set pagesize 1000 linesize 300 trimspool on verify off feedback off
column owner     format a20
column cons_name format a35
column tbl_name  format a35
column pos       format 99999
column col_name  format a35

accept o prompt 'OWNER (blank=all): '

select owner,
       constraint_name cons_name,
       table_name      tbl_name,
       position         pos,
       column_name     col_name
from dba_cons_columns
where ('&o' = '' or owner = upper('&o'))
order by owner, cons_name, pos;
