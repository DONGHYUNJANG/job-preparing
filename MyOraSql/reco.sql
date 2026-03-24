col name for a45;
select a.file# as file_num, b.name as name from v$recover_file a 
join v$datafile b on a.file# = b.file#;
