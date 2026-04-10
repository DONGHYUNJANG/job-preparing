-- =================================================
-- 🗂️ Oracle Parameter Checker (RAC Global)
-- =================================================
-- 사용법: SQL> @check_param [파라미터명]
-- 예시: SQL> @check_param db_files
-- =================================================

-- 1. 화면 출력 포맷 설정
SET VERIFY OFF
SET LINESIZE 150
SET PAGESIZE 100
COLUMN inst_id FORMAT 9999 HEAD 'INST'
COLUMN name FORMAT a30 HEAD 'PARAMETER NAME'
COLUMN value FORMAT a40 HEAD 'VALUE'
COLUMN issys_modifiable FORMAT a15 HEAD 'SYS_MODIFIABLE'

-- 2. 쿼리 실행 (LIKE 조건 및 대소문자 무시)
SELECT 
    inst_id, 
    name, 
    value, 
    issys_modifiable
FROM 
    gv$parameter
WHERE 
    lower(name) LIKE lower('%&1%')
ORDER BY
    inst_id, name;

-- 3. 포맷 초기화
CLEAR COLUMNS
SET VERIFY ON
