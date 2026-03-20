-- user_cols.sql : user_tab_columns (자주 보는 컬럼만)
set pagesize 1000 linesize 320 trimspool on verify off feedback off
column col_id     format 99999
column col_name   format a35
column data_type  format a20
column len         format 9999999
column nullable   format a3
column defv        format a35


select column_id col_id,
       column_name col_name,
       data_type data_type,
       data_length len,
       nullable,
       substr(data_default, 1, 35) defv
from user_tab_columns
order by table_name, column_id;

