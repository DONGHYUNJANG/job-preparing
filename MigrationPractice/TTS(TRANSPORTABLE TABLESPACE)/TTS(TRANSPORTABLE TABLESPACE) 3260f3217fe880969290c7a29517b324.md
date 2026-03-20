# TTS(TRANSPORTABLE TABLESPACE)

## 📋**Character Set** 체크 방법

<aside>
✅

**Export 대상 DB와 Import 대상 DB의 Character Set이 동일해야 합니다.**

</aside>

```sql
SELECT *
FROM   database_properties
WHERE  property_name = 'NLS_CHARACTERSET';

SELECT *
FROM   database_properties
WHERE  property_name = 'NLS_NCHAR_CHARACTERSET';
```

## 📋 TTS Self-Contained 체크 방법

### 1. 체크 실행 (`DBMS_TTS.TRANSPORT_SET_CHECK`)

확인하고 싶은 테이블스페이스 이름을 넣고 아래 프로시저를 실행합니다. (예: `USERS` 테이블스페이스)

```jsx
- 1. 체크 수행 (메모리에 결과 저장)
EXEC DBMS_TTS.TRANSPORT_SET_CHECK('USERS', TRUE);
```

- `TRUE` 옵션: 제약 조건(Constraints)까지 꼼꼼하게 검사하겠다는 뜻입니다.

### 2. 결과 확인 (`TRANSPORT_SET_VIOLATIONS`)

위 명령은 화면에 바로 결과를 뿌려주지 않습니다. 대신 **`TRANSPORT_SET_VIOLATIONS`** 뷰를 조회해서 위반 사항이 있는지 확인해야 합니다.

```jsx
- 2. 위반 사항 조회
SELECT * FROM TRANSPORT_SET_VIOLATIONS;
```

- **결과가 0건(Empty):** 문제없음

## 📋 Edian 확인

```jsx
SELECT b.platform_name, b.endian_format
FROM   v$database a, v$transportable_platform b
WHERE  a.platform_name = b.platform_name;
```

## 📋실습 구성(요약)

- **Source**: Oracle 12c
- **Target**: Oracle 19c
- **이관 단위**: tablespace `ts10000`
- **스키마 리맵**: `hr` → `hr2`

## 📋[12c] TTS Export (tablespace 단위)

### 3-1. tablespace READ ONLY 전환

```sql
SELECT t.name, d.enabled, d.name
FROM   v$tablespace t, v$datafile d
WHERE  t.ts# = d.ts#;

ALTER TABLESPACE ts10000 READ ONLY;

SQL> select TABLESPACE_NAME, STATUS from user_tablespaces;

TABLESPACE_NAME                STATUS
------------------------------ ---------
TS10000                        READ ONLY

```

### 3-2. expdp (transport_tablespace)

```sql
expdp directory=datapump_dir dumpfile=ts10000.dmp transport_tablespace=y tablespaces=ts10000
```

### 3-3. 데이터파일 + 덤프파일 전송(scp)

```sql
scp /home/oracle/pump_ora12c/ts10000.dmp oracle@192.168.13.181:/home/oracle/pump_ora19c/
```

```sql
scp /u01/app/oracle/oradata/ora12/ts10000.dbf oracle@192.168.13.181:/home/oracle/oradata
```

> SEQUENCE / VIEW 이관: 메타데이터만 별도 expdp/impdp
> 

### 4-1. [12c] 메타데이터 전용 Export

- 목적: **SEQUENCE / VIEW / PROCEDURE 등 딕셔너리 객체를 데이터 없이(구조만) 추출**
- 이미 TTS로 옮긴 객체(TABLE/INDEX/CONSTRAINT/TRIGGER 등)는 제외

```bash
expdp SCHEMAS=hr \
  DIRECTORY=datapump_dir \
  DUMPFILE=hr_meta.dmp \
  LOGFILE=hr_meta_exp.log \
  CONTENT=METADATA_ONLY \
  EXCLUDE=TABLE,INDEX,CONSTRAINT,TRIGGER
```

### 4-2. 덤프파일을 19c로 복사

```bash
scp /home/oracle/pump_ora12c/hr_meta.dmp oracle@192.168.13.181:/home/oracle/pump_ora19c/
```

> [19c] TTS Import (hr → hr2)
> 

## 4-3. tablespace READ WRITE 복구

```sql
ALTER TABLESPACE ts10000 READ WRITE;
```

### 5-1. [19c] hr2 사용자 생성

```sql
SHUTDOWN IMMEDIATE;
STARTUP;

DROP USER hr2 CASCADE;

CREATE USER hr2
  IDENTIFIED BY hr2;

GRANT CONNECT, RESOURCE TO hr2;
GRANT CREATE VIEW TO hr2;
GRANT CREATE SEQUENCE TO hr2;
```

### 5-2. [19c] 데이터 Import (hr → hr2)

```jsx
impdp transport_datafiles='/home/oracle/oradata/ts10000.dbf' directory=datapump_dir dumpfile=ts10000.dmp remap_schema=hr:hr2

```

### 5-3. [19c] 메타데이터 Import (hr → hr2)

```bash
impdp DIRECTORY=datapump_dir DUMPFILE=hr_meta.dmp LOGFILE=hr_meta_imp.log REMAP_SCHEMA=hr:hr2
```

## 6. tablespace READ WRITE 복구

```sql
ALTER TABLESPACE ts10000 READ WRITE;

GRANT CREATE DATABASE LINK TO hr2;
ALTER USER hr2 IDENTIFIED BY hr2;
```

## 7) 이관 검증(12c ↔ 19c 비교)

### 7-1. DB Link 생성(예시)

```sql
**!!!!! 반드시 hr유저로 접속**
DROP DATABASE LINK hr_link;

CREATE DATABASE LINK hr_link
CONNECT TO hr
IDENTIFIED BY hr
USING '192.168.13.81:1521/ora12';
```

### 7-2. 객체 비교 쿼리(차집합)

```sql
-- 테이블
SELECT table_name FROM user_tables
MINUS
SELECT table_name FROM user_tables@hr_link;

SELECT table_name FROM user_tables@hr_link
MINUS
SELECT table_name FROM user_tables;

-- 인덱스
SELECT index_name FROM user_indexes
MINUS
SELECT index_name FROM user_indexes@hr_link;

SELECT index_name FROM user_indexes@hr_link
MINUS
SELECT index_name FROM user_indexes;

-- 제약
SELECT constraint_name FROM user_constraints
MINUS
SELECT constraint_name FROM user_constraints@hr_link;

SELECT constraint_name FROM user_constraints@hr_link
MINUS
SELECT constraint_name FROM user_constraints;

-- 시퀀스
SELECT sequence_name FROM user_sequences
MINUS
SELECT sequence_name FROM user_sequences@hr_link;

SELECT sequence_name FROM user_sequences@hr_link
MINUS
SELECT sequence_name FROM user_sequences;

-- 시너님
SELECT synonym_name FROM user_synonyms
MINUS
SELECT synonym_name FROM user_synonyms@hr_link;

SELECT synonym_name FROM user_synonyms@hr_link
MINUS
SELECT synonym_name FROM user_synonyms;

-- 뷰
SELECT view_name FROM user_views
MINUS
SELECT view_name FROM user_views@hr_link;

SELECT view_name FROM user_views@hr_link
MINUS
SELECT view_name FROM user_views;
```

### 8. INVALID상태의 객체가 있는지 확인

```jsx
-- 전체 데이터베이스에서 Invalid 객체 확인 (DBA 권한 필요)
SELECT owner, object_type, object_name, status
FROM dba_objects
WHERE status = 'INVALID'
ORDER BY owner, object_type, object_name;

-- 현재 접속한 계정의 Invalid 객체 확인
SELECT object_type, object_name, status
FROM user_objects
WHERE status = 'INVALID'
ORDER BY object_type, object_name;
```

### 9. 무효화된 객체 일괄 재컴파일 (utlrp.sql) - 무효화된 객체가 존재하는 경우

- **방법:** SQL*Plus에서 `SYS` 권한으로 실행SQL
    
    `@?/rdbms/admin/utlrp.sql`
    

<aside>
💡

**완료후 link, 유저 권한, role, quota, 임시파일 등 정리할것**

오브젝즈 중에 ivalid된것이 있는지 확인할것

특히 rad/write상태로 돌린것 확인할것!!

</aside>

[왜 TTS만으로는 SEQUENCE / VIEW가 TTS로 이관되지 않았나?](https://www.notion.so/TTS-SEQUENCE-VIEW-TTS-3260f3217fe880f5872ae87b01ce615c?pvs=21)

[**TTS 테이블스페이스 이름 및 경로 규칙**](https://www.notion.so/TTS-3260f3217fe88050b08ad888d5ae89b7?pvs=21)

[데이터 이행 후 제약조건 및 인덱스 이름 차이가 나는 경우](https://www.notion.so/3260f3217fe880648fcbf2651d28df75?pvs=21)

[멀티 테이블스페이스 TTS (Multi-Tablespace TTS)](https://www.notion.so/TTS-Multi-Tablespace-TTS-3260f3217fe8804a84d6e877004e1cc9?pvs=21)