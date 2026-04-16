![image.png](attachment:96f14000-803c-4122-8488-645880f66dff:image.png)

### 관리자 인증 (Administrator Authentication)

<aside>
🔐

**정의**

관리자 인증은 Oracle DB의 특권 권한(SYSDBA, SYSOPER, SYSASM 등)으로 접속할 수 있는 주체를 검증하는 방식입니다.

</aside>

### 1. 운영 체제(OS) 보안

- Oracle DBA는 일반 DB 유저와 **OS 레벨에서부터 구분**됩니다.

| 구분 | OS 권한 |
| --- | --- |
| DBA | 데이터 파일 생성/삭제 가능 |
| 일반 DB 유저 | 데이터 파일 생성/삭제 **불가** |
- 즉, DBA는 Oracle 계정(`oracle` 유저) 또는 `dba` 그룹 소속이어야 합니다.
- 일반 유저는 SQL로만 접근하며, OS 파일 시스템을 직접 변경할 수 없습니다.

### 관련실습:

```sql
[oracle@ora19c ~]$ su -
암호:
마지막 로그인: 수  3월 11 10:56:14 KST 2026 일시 pts/0
[root@ora19c ~]#
[root@ora19c ~]#
[root@ora19c ~]# useradd oracle2
[root@ora19c ~]#
[root@ora19c ~]# id oracle2
uid=1001(oracle2) gid=1001(oracle2) groups=1001(oracle2)
[root@ora19c ~]#
[root@ora19c ~]# su - oracle2
마지막 로그인: 수  3월 11 10:56:18 KST 2026 일시 pts/0
[oracle2@ora19c ~]$
[oracle2@ora19c ~]$ sqlplus  / as sysdba
bash: sqlplus: 명령을 찾을 수 없습니다...
[oracle2@ora19c ~]$
[oracle2@ora19c ~]$ su -

[root@ora19c ~]# usermod -aG dba oracle2
[root@ora19c ~]#
[root@ora19c ~]# id oracle2
uid=1001(oracle2) gid=1001(oracle2) groups=1001(oracle2),54322(dba)
[root@ora19c ~]#
[root@ora19c ~]# su - oracle2
마지막 로그인: 수  3월 11 10:58:59 KST 2026 일시 pts/0
[oracle2@ora19c ~]$
[oracle2@ora19c ~]$
[oracle2@ora19c ~]$ sqlplus / as sysdba
bash: sqlplus: 명령을 찾을 수 없습니다...
[oracle2@ora19c ~]$
[oracle2@ora19c ~]$ . oraenv
ORACLE_SID = [oracle2] ? orcl
ORACLE_BASE environment variable is not being set since this
information is not available for the current user ID oracle2.
You can set ORACLE_BASE manually if it is required.
Resetting ORACLE_BASE to its previous value or ORACLE_HOME
The Oracle base has been set to /u01/app/oracle/product/19.3.0/dbhome_1
[oracle2@ora19c ~]$
[oracle2@ora19c ~]$ echo $ORACLE_HOME
/u01/app/oracle/product/19.3.0/dbhome_1
[oracle2@ora19c ~]$
[oracle2@ora19c ~]$ sqlplus / as sysdba

SQL*Plus: Release 19.0.0.0.0 - Production on Wed Mar 11 11:00:39 2026
Version 19.26.0.0.0

Copyright (c) 1982, 2024, Oracle.  All rights reserved.

??? ???:
Oracle Database 19c Enterprise Edition Release 19.0.0.0.0 - Production
Version 19.26.0.0.0

SQL>

```

### 2. 관리자 인증 방식 2가지

#### ① OS 인증

```bash
# oracle 유저로 OS 로그인 후
sqlplus / as sysdba   # 비밀번호 없이 접속 가능
```

- OS의 `dba` 그룹 소속이면 **비밀번호 없이** SYSDBA 접속이 허용됩니다.
- **로컬 서버에서만** 동작합니다.
- 감사(Audit) 기록에는 **OS 계정 이름**이 남습니다.

#### ② Password File 인증

```bash
# 원격에서 접속할 때
sqlplus sys/oracle@orcl as sysdba
```

- `orapwd`로 생성한 Password File 기반으로 인증합니다.
- **원격 접속(네트워크)** 에서 사용합니다.
- 감사(Audit) 기록에는 **DB 유저 이름**이 남습니다.
- **대소문자 구분**이 적용됩니다. (Oracle 11g부터 기본)