-- user_seg_f.sql : user_segments 전체 조회
set pagesize 1000 linesize 280 trimspool on verify off feedback off
column seg_name  format a30
column part_name format a22
column seg_type  format a22
column tbs_space format a20
column bytes_    format 999999999999999
column blocks    format 999999999999
column extents   format 999999

select segment_name seg_name,
       partition_name part_name,
       segment_type seg_type,
       tablespace_name tbs_space,
       bytes bytes_,
       blocks,
       extents
from user_segments
order by segment_type, segment_name, partition_name;
