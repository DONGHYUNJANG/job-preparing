-- user_seg.sql : user_segments (세그먼트 크기/타입 요약)
set pagesize 1000 linesize 280 trimspool on verify off feedback off
column seg_name  format a30
column part_name format a22
column seg_type  format a22
column tbs_space format a20
column bytes_    format 999999999999999
column blocks    format 999999999999
column extents   format 999999

accept sn prompt 'SEGMENT_NAME (blank=all): '
accept ty prompt 'SEGMENT_TYPE (blank=all): '

select segment_name seg_name,
       partition_name part_name,
       segment_type seg_type,
       tablespace_name tbs_space,
       bytes bytes_,
       blocks,
       extents
from user_segments
where ('&sn' = '' or segment_name = upper('&sn'))
  and ('&ty' = '' or segment_type = upper('&ty'))
order by segment_type, segment_name, partition_name;
