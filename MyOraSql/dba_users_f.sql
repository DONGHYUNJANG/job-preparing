-- dba_users_f.sql : DBA_USERS 전체 조회 (계정 상태 / 기본·임시 테이블스페이스)
set pagesize 1000 linesize 260 trimspool on verify off feedback off
column username             format a25
column account_status       format a25
column default_tablespace   format a20
column temporary_tablespace format a20

select username,
       account_status,
       default_tablespace,
       temporary_tablespace,
       user_id
from dba_users
order by username;
