-- dba_cons.sql : dba_constraints (자주 보는 컬럼만)
set pagesize 1000 linesize 320 trimspool on verify off feedback off
column owner     format a20
column cons_name format a35
column tbl_name  format a35
column ctype     format a10
column status    format a12
column deferr    format a6
column deferred  format a6
column valided   format a7
column del_rule  format a10
column rcons     format a35


select owner,
       constraint_name cons_name,
       table_name      tbl_name,
       constraint_type ctype,
       status,
       deferrable      deferr,
       deferred        deferred,
       validated       valided,
       r_constraint_name rcons,
       delete_rule     del_rule
from dba_constraints
order by owner, status, constraint_type, cons_name;

