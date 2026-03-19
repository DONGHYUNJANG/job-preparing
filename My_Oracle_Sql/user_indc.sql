-- user_indc.sql : user_ind_columns (인덱스 컬럼 순서 확인용)
set pagesize 1000 linesize 360 trimspool on verify off feedback off
column owner    format a20
column idx_name format a35
column tbl_name format a35
column col_pos  format 99999
column col_name format a35
column descend  format a3
column col_len  format 9999999

accept t prompt 'TABLE_NAME (blank=all): '
accept i prompt 'INDEX_NAME (blank=all): '

select index_name idx_name,
       table_name tbl_name,
       column_position col_pos,
       column_name col_name,
       descend,
       column_length col_len
from user_ind_columns
where ('&t' = '' or table_name = upper('&t'))
  and ('&i' = '' or index_name = upper('&i'))
order by table_name, index_name, column_position;

