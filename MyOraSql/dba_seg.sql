-- dba_seg.sql : dba_segments (스키마별 세그먼트 크기/타입 요약)
set pagesize 1000 linesize 300 trimspool on verify off feedback off
column owner     format a18
column seg_name  format a28
column part_name format a20
column seg_type  format a20
column tbs_space format a18
column bytes_    format 999999999999999
column blocks    format 999999999999
column extents   format 999999

accept o prompt 'OWNER (blank=all): '

select owner,
       segment_name seg_name,
       partition_name part_name,
       segment_type seg_type,
       tablespace_name tbs_space,
       bytes bytes_,
       blocks,
       extents
from dba_segments
where ('&o' = '' or owner = upper('&o'))
order by owner, segment_type, segment_name, partition_name;
