-- user_idx_p.sql : user_ind_partitions (파티션만, 자주 보는 컬럼만)
set pagesize 1000 linesize 380 trimspool on verify off feedback off
column tbl_name   format a30
column idx_name   format a35
column part_name  format a30
column part_pos   format 99999
column tbs_space  format a20
column status     format a12
column blevel     format 99999
column leaf_b     format 999999999
column distinct_k format 999999999
column clust_f    format 999999999999
column hi_v       format a60


select table_name       tbl_name,
       index_name       idx_name,
       partition_name   part_name,
       partition_position part_pos,
       tablespace_name  tbs_space,
       status,
       blevel,
       leaf_blocks      leaf_b,
       distinct_keys    distinct_k,
       clustering_factor clust_f,
       substr(high_value, 1, 200) hi_v
from user_ind_partitions
order by table_name, index_name, partition_position;

