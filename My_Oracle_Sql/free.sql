-- 1. 출력 폭 설정
COLUMN TS_NAME FORMAT a15
COLUMN ALLOC_MB FORMAT 9,999,999
COLUMN USED_MB FORMAT 9,999,999
COLUMN FREE_MB FORMAT 9,999,999
COLUMN USED_PCT FORMAT 999.99

-- 2. 사용률 조회 쿼리
SELECT 
    d.tablespace_name AS TS_NAME,
    ROUND(d.total_bytes / 1024 / 1024, 2) AS ALLOC_MB,
    ROUND((d.total_bytes - NVL(f.free_bytes, 0)) / 1024 / 1024, 2) AS USED_MB,
    ROUND(NVL(f.free_bytes, 0) / 1024 / 1024, 2) AS FREE_MB,
    ROUND((d.total_bytes - NVL(f.free_bytes, 0)) / d.total_bytes * 100, 2) AS USED_PCT
FROM 
    (SELECT tablespace_name, SUM(bytes) AS total_bytes 
     FROM dba_data_files 
     GROUP BY tablespace_name) d,
    (SELECT tablespace_name, SUM(bytes) AS free_bytes 
     FROM dba_free_space 
     GROUP BY tablespace_name) f
WHERE 
    d.tablespace_name = f.tablespace_name(+)
ORDER BY USED_PCT DESC;
