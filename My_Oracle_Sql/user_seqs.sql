-- user_seqs.sql : user_sequences (자주 쓰는 값만)
set pagesize 1000 linesize 260 trimspool on verify off feedback off
column seq_name format a40
column inc_by   format 999999999
column min_v    format 999999999999999999
column max_v    format 999999999999999999
column last_no  format 999999999999999999
column cache_sz format 9999999
column cycle_f  format a3
column order_f  format a3

accept s prompt 'SEQUENCE_NAME (blank=all): '

select sequence_name seq_name,
       increment_by  inc_by,
       min_value     min_v,
       max_value     max_v,
       last_number   last_no,
       cache_size    cache_sz,
       cycle_flag    cycle_f,
       order_flag    order_f
from user_sequences
where ('&s' = '' or sequence_name = upper('&s'))
order by seq_name;

