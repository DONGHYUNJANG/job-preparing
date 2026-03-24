-- 1. 출력 환경 설정 (스크롤 방지 및 가독성 향상)
SET LINESIZE 200
SET PAGESIZE 100
COL INDEX_OWNER FOR A15
COL INDEX_NAME FOR A25
COL PARTITION_NAME FOR A20
COL STATUS FOR A15

-- 2. 인덱스 파티션 상태 확인 쿼리
SELECT 
    index_owner, 
    index_name, 
    partition_name, 
    status
FROM 
    dba_ind_partitions
WHERE 
    index_name IN (
        SELECT index_name 
        FROM dba_indexes 
        WHERE table_name = 'SALES'
    )
ORDER BY 
    index_name, 
    partition_name;


SELECT 
    index_owner, 
    index_name, 
    partition_name, 
    status
FROM 
    dba_ind_partitions
WHERE 
    index_name IN (
        SELECT index_name 
        FROM dba_indexes 
        WHERE table_name = 'COSTS'
    )
ORDER BY 
    index_name, 
    partition_name;