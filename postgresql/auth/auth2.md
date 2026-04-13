**최소 권한의 원칙 (Principle of Least Privilege)**

**정의**

유저에게 업무 수행에 필요한 **최소한의 권한만 부여**하는 보안 원칙입니다. 과도한 권한은 실수나 악의적 공격 시 피해 범위를 키우므로, Oracle 보안의 기본 철학이기도 합니다.

### 항목별 상세 설명

#### 1) 데이터 딕셔너리 보호

```sql
O7_DICTIONARY_ACCESSIBILITY = FALSE  -- 기본값 (권장)
```

- `FALSE`: **SYSDBA 권한 없이는** 딕셔너리 객체(SYS 소유)에 접근 불가
- `TRUE`: ANY 권한(예: `SELECT ANY TABLE`)만으로도 딕셔너리 조회가 가능해져 위험
- Oracle 10g부터 기본값이 `FALSE`로 변경

```sql
SHOW PARAMETER O7_DICTIONARY_ACCESSIBILITY;
```

#### 2) PUBLIC 권한 정리

PUBLIC은 **DB의 모든 유저에게 자동 적용되는 묵시적 그룹**입니다.

```sql
-- PUBLIC에 부여된 권한 확인
SELECT PRIVILEGE, OBJECT_NAME
FROM DBA_TAB_PRIVS
WHERE GRANTEE = 'PUBLIC';

-- 불필요한 권한 회수 예시
REVOKE EXECUTE ON UTL_FILE FROM PUBLIC;
REVOKE EXECUTE ON UTL_HTTP FROM PUBLIC;
REVOKE EXECUTE ON DBMS_ADVISOR FROM PUBLIC;
```

- PUBLIC에 부여된 권한은 곧 **모든 유저가 가진 권한**이므로, 최소화가 필수

#### 3) 디렉토리 접근 제한

```sql
-- 특정 유저에게만 디렉토리 권한 부여
GRANT READ, WRITE ON DIRECTORY data_dir TO scott;

-- 불필요한 권한 회수
REVOKE READ ON DIRECTORY data_dir FROM PUBLIC;
```

- 디렉토리 객체는 OS 파일 접근과 연결되므로, **필요한 계정에만** 최소 권한 부여

#### 4) 관리 권한(DBA Role 등) 최소화

```sql
-- DBA 권한 보유자 확인
SELECT GRANTEE
FROM DBA_ROLE_PRIVS
WHERE GRANTED_ROLE = 'DBA';

-- 필요한 권한만 개별 부여 (DBA Role 대신)
GRANT CREATE SESSION, CREATE TABLE TO dev_user;
```

- DBA Role은 200개 이상의 권한이 포함된 묶음
- 꼭 필요한 유저에게만 부여하고, 가능하면 **개별 권한 부여로 대체**

#### 5) 원격 OS 인증 차단

```sql
REMOTE_OS_AUTHENT = FALSE  -- 기본값 (권장)
```

- `TRUE`: 원격 클라이언트의 **OS 계정 이름만으로 DB 접속**이 가능해져 심각한 취약점
- **반드시 `FALSE` 유지** 권장
- 변경 시 DB 재시작 필요

```sql
SHOW PARAMETER REMOTE_OS_AUTHENT;
```

### 전체 요약

| 항목 | 핵심 조치 |
| --- | --- |
| 딕셔너리 보호 | `O7_DICTIONARY_ACCESSIBILITY =FALSE` |
| PUBLIC 권한 | 불필요한 패키지 권한 회수 |
| 디렉토리 | 필요한 유저에게만 READ/WRITE 부여 |
| 관리 권한 | DBA Role 최소화, 개별 권한 부여 원칙 |
| 원격 OS 인증 | `REMOTE_OS_AUTHENT = FALSE` 유지 |

## 실습

```sql
1. o7_dictionary_accessibility  파라미터 설정값 조정

SQL> show parameter o7

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
O7_DICTIONARY_ACCESSIBILITY          boolean     FALSE
SQL>
SQL>
SQL>
SQL> create user smith
  2  identified by tiger;

User created.

SQL> grant connect, resource to smith;

Grant succeeded.

SQL> connect smith/tiger
Connected.
SQL>
SQL> select table_name
  2   from dba_tables;
 from dba_tables
      *
ERROR at line 2:
ORA-00942: table or view does not exist

SQL> connect scott/tiger
Connected.
SQL>
SQL> select * from dept;

    DEPTNO DNAME          LOC
---------- -------------- -------------
        10 ACCOUNTING     NEW YORK
        20 RESEARCH       DALLAS
        30 SALES          CHICAGO
        40 OPERATIONS     BOSTON

SQL> connect / as sysdba
Connected.
SQL>
SQL> grant select any table to smith;

Grant succeeded.

SQL>

SQL> connect smith/tiger
Connected.
SQL>
SQL> select *
  2   from scott.dept;

    DEPTNO DNAME          LOC
---------- -------------- -------------
        10 ACCOUNTING     NEW YORK
        20 RESEARCH       DALLAS
        30 SALES          CHICAGO
        40 OPERATIONS     BOSTON

SQL> select table_name from dba_tables;
select table_name from dba_tables
                       *
ERROR at line 1:
ORA-00942: table or view does not exist

SQL>
SQL> connect / as sysdba
Connected.
SQL>
SQL> show parameter o7

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
O7_DICTIONARY_ACCESSIBILITY          boolean     FALSE
SQL>
SQL>

smith 가 select any table 권한 받았지만 O7_DICTIONARY_ACCESSIBILITY 가 false 이기 때문에
dba_ 로 시작하는 data dictionary 를 볼 수 없는겁니다. 

```

### 문제1. O7_DICTIONARY_ACCESSIBILITY  를 true 로 켜고 smith 에서 dba_tables 볼 수 있는지 확인하시요

```sql

SQL> shutdown immediate
Database closed.
Database dismounted.
ORACLE instance shut down.
SQL>
SQL> startup
ORACLE instance started.

Total System Global Area  481259520 bytes
Fixed Size                  1337352 bytes
Variable Size             318769144 bytes
Database Buffers          155189248 bytes
Redo Buffers                5963776 bytes
Database mounted.
Database opened.
SQL>
SQL>
SQL> show parameter o7

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
O7_DICTIONARY_ACCESSIBILITY          boolean     TRUE
SQL>
SQL> connect smith/tiger
Connected.
SQL>
SQL> select count(*)
  2   from dba_tables;

  COUNT(*)
----------
      2785

SQL>

SQL> connect / as sysdba
Connected.
SQL>
SQL>
SQL>  alter system set O7_DICTIONARY_ACCESSIBILITY=false scope=spfile;

System altered.

SQL>
SQL> shutdown immediate
Database closed.
Database dismounted.
ORACLE instance shut down.
SQL>
SQL>
SQL> startup
ORACLE instance started.

Total System Global Area  481259520 bytes
Fixed Size                  1337352 bytes
Variable Size             318769144 bytes
Database Buffers          155189248 bytes
Redo Buffers                5963776 bytes
Database mounted.
Database opened.
SQL>

```

## 실습2. remote_os_authent  파라미터 활성화후 접속 테스트하기

```sql
[king@ora19c ~]$ sqlplus /@192.168.13.181:1521/orcl

SQL*Plus: Release 19.0.0.0.0 - Production on Wed Mar 11 14:07:01 2026
Version 19.26.0.0.0

Copyright (c) 1982, 2024, Oracle.  All rights reserved.

ERROR:
ORA-01017: ????/????? ???, ???? ? ????.

Enter user-name:

[root@ora19c ~]# su - oracle
마지막 로그인: 수  3월 11 11:32:04 KST 2026 일시 pts/0
[oracle@ora19c ~]$
[oracle@ora19c ~]$ sys

SQL*Plus: Release 19.0.0.0.0 - Production on Wed Mar 11 14:08:08 2026
Version 19.26.0.0.0

Copyright (c) 1982, 2024, Oracle.  All rights reserved.

Connected to:
Oracle Database 19c Enterprise Edition Release 19.0.0.0.0 - Production
Version 19.26.0.0.0

SQL> show parameter remote

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
remote_dependencies_mode             string      TIMESTAMP
remote_listener                      string
remote_login_passwordfile            string      EXCLUSIVE
remote_os_authent                    boolean     FALSE
remote_os_roles                      boolean     FALSE
remote_recovery_file_dest            string
result_cache_remote_expiration       integer     0
SQL>
SQL>
SQL>
SQL> alter system set remote_os_authent=true scope=spfile;

System altered.

SQL> shutdown immediate
Database closed.
Database dismounted.
ORACLE instance shut down.

SQL> alter system set remote_os_authent=true scope=spfile;

System altered.

SQL> shutdown immediate
Database closed.
Database dismounted.
ORACLE instance shut down.
SQL>
SQL> startup
ORA-32004: obsolete or deprecated parameter(s) specified for RDBMS instance

SQL> show parameter remote

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
remote_dependencies_mode             string      TIMESTAMP
remote_listener                      string
remote_login_passwordfile            string      EXCLUSIVE
remote_os_authent                    boolean     TRUE
remote_os_roles                      boolean     FALSE
remote_recovery_file_dest            string
result_cache_remote_expiration       integer     0
SQL>
SQL>

[king@ora19c ~]$ sqlplus /@192.168.13.181:1521/orcl

SQL*Plus: Release 19.0.0.0.0 - Production on Wed Mar 11 14:09:52 2026
Version 19.26.0.0.0

Copyright (c) 1982, 2024, Oracle.  All rights reserved.

??? ??? ??? ??: ?  3?   11 2026 14:05:38 +09:00

??? ???:
Oracle Database 19c Enterprise Edition Release 19.0.0.0.0 - Production
Version 19.26.0.0.0

SQL>
SQL> show user
USER? "KING"???
SQL>

-- 다시 false 로 변경합니다.

SQL> alter system set remote_os_authent=false scope=spfile;

System altered.

SQL> startup force

```