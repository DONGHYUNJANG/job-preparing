col name for a50;

SELECT 
    a.file#, 
    a.status, 
    a.change#, 
    b.name,
    c.checkpoint_change# 
FROM v$backup a
JOIN v$datafile b ON a.file# = b.file#
JOIN v$datafile_header c ON b.file# = c.file#;


