-- 1. SQL*Plus 출력 포맷 설정 (기존과 동일)
SET LINESIZE 160
SET PAGESIZE 100
COLUMN "테이블명" FORMAT A15
COLUMN "FK 컬럼" FORMAT A15
COLUMN "참조 테이블" FORMAT A15
COLUMN "참조 컬럼" FORMAT A15
COLUMN "삭제 규칙" FORMAT A12
COLUMN "상태" FORMAT A10
COLUMN "지연속성" FORMAT A12

-- 2. 사용자로부터 입력받아 실행하는 쿼리
SELECT 
    a.table_name AS "테이블명", 
    a.column_name AS "FK 컬럼", 
    c.table_name AS "참조 테이블", 
    c.column_name AS "참조 컬럼",
    b.delete_rule AS "삭제 규칙",
    b.status AS "상태",
    b.deferrable AS "지연속성"
FROM 
    user_cons_columns a
JOIN 
    user_constraints b ON a.constraint_name = b.constraint_name
JOIN 
    user_cons_columns c ON b.r_constraint_name = c.constraint_name
WHERE 
    b.constraint_type = 'R' 
    AND a.table_name = UPPER('&target_table_name');
