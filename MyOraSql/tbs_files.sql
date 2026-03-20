-- tbs_files.sql : DBA_DATA_FILES (데이터파일 목록/용량/자동확장)
set pagesize 1000 linesize 340 trimspool on verify off feedback off
column tablespace_name format a30
column file_name       format a70
column bytes_mb        format 999,999,999,990.99
column autoextensible  format a3
column max_mb          format 999,999,999,990.99
column increment_by    format 999,999,999

select tablespace_name,
       file_name,
       round(bytes / 1024 / 1024, 2) bytes_mb,
       case when autoextensible = 'YES' then 'Y' else 'N' end autoextensible,
       round(maxbytes / 1024 / 1024, 2) max_mb,
       increment_by
from dba_data_files
order by tablespace_name, file_name;

