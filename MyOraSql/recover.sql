col name for a150
select r.file#, d.name as name
       from v$recover_file  r, v$datafile  d
       where r.file#=d.file#
/