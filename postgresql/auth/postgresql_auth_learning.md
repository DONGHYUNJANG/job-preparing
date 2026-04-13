# PostgreSQL 관리자 인증 (Administrator Authentication) 개념 및 변환

Oracle의 관리자 인증(OS 인증, Password File 인증)과 유사한 개념이 PostgreSQL에서는 어떻게 구현되는지, 그리고 어떻게 다르게 동작하는지 알아봅니다.

## 1. Oracle과 PostgreSQL의 관리자 권한 차이점

| 특징 | Oracle | PostgreSQL |
| --- | --- | --- |
| **최고 관리자 계정** | `SYS`, `SYSTEM` (권한: `SYSDBA`) | `postgres` (속성: `SUPERUSER`) |
| **OS 레벨 보안** | `oracle` OS 유저 및 `dba` 그룹 멤버십에 의존 | `postgres` OS 유저가 기본. 그룹 멤버십보다는 `pg_hba.conf` 설정 파일에 의존 |
| **로컬 관리자 인증** | OS 인증 (`sqlplus / as sysdba`) | Peer 인증 (`psql -U postgres`) |
| **원격 관리자 인증** | 패스워드 파일 (`orapwd`) | 패스워드 인증 (`pg_hba.conf`의 `scram-sha-256`, `md5`) |

---

## 2. PostgreSQL의 인증 방식 (pg_hba.conf)

PostgreSQL은 모든 클라이언트의 인증 방식을 **`pg_hba.conf` (Host-Based Authentication)** 라는 하나의 텍스트 파일에서 중앙 집중적으로 관리합니다. 이 파일의 설정에 따라 OS 인증을 할지, 패스워드 인증을 할지 결정됩니다.

### ① OS 인증 방식 (Peer Authentication)

Oracle의 **OS 인증(`sqlplus / as sysdba`)** 과 동일한 역할을 하는 것이 PostgreSQL의 **Peer 인증**입니다.
주로 데이터베이스 서버 로컬(Local)에서 접속할 때 사용됩니다.

- **원리:** 현재 로그인한 OS 유저의 이름과 PostgreSQL DB 유저(Role)의 이름이 일치하면, **비밀번호 없이 접속을 허용**합니다.
- **예시:** OS의 `postgres` 유저로 로그인한 상태에서 DB의 `postgres` (슈퍼유저) 계정으로 접속.

**실습: 로컬에서 Peer 인증으로 비밀번호 없이 접속하기**

```bash
# 1. OS의 postgres 유저로 전환 (root 권한 필요)
[root@pgserver ~]# su - postgres

# 2. 비밀번호 없이 psql 명령어만으로 슈퍼유저(postgres)로 접속
[postgres@pgserver ~]$ psql
psql (14.5)
Type "help" for help.

postgres=# 
```

만약 새로운 계정을 만들고 OS 인증을 사용하고 싶다면, PostgreSQL 유저명과 동일한 OS 유저를 생성하면 됩니다. (단, `pg_hba.conf`에 `local all all peer` 설정이 되어 있어야 합니다.)

### ② 패스워드 인증 방식 (Password Authentication)

Oracle의 **Password File 인증**처럼 원격 네트워크 접속 시 주로 사용되는 방식입니다. PostgreSQL은 별도의 패스워드 파일을 만들지 않고, DB 내부에 저장된 해시 패스워드와 `pg_hba.conf`의 설정을 통해 인증합니다.

- **원리:** 클라이언트가 네트워크(TCP/IP)를 통해 접속할 때 비밀번호를 요구하며, 안전한 해시 알고리즘(주로 `scram-sha-256` 또는 `md5`)을 통해 검증합니다.
- 원격에서 접속하는 모든 유저(일반 유저 `scott`이든 슈퍼유저 `postgres`이든)에게 동일하게 적용됩니다.

**실습: 원격에서 관리자/일반 유저로 접속하기**

```bash
# 원격지 서버에서 패스워드를 입력하여 접속 (-h: 호스트, -U: 유저명)
[user@client ~]$ psql -h 192.168.1.10 -U postgres
Password for user postgres: (비밀번호 입력)

[user@client ~]$ psql -h 192.168.1.10 -U scott -d postgres
Password for user scott: (비밀번호 입력)
```

> **참고:** PostgreSQL은 Oracle의 `SYSDBA`처럼 접속 시 특별한 모드(`as sysdba`)를 명시하지 않습니다. 계정 자체가 `SUPERUSER` 속성을 가지고 있다면, 일반 접속과 동일하게 로그인한 후 관리자 명령을 수행할 수 있습니다.

---

## 3. 실습: 새로운 슈퍼유저(관리자) 생성 및 권한 확인

Oracle에서 `dba` 그룹에 사용자를 추가하여 OS 인증을 허용했던 실습을 PostgreSQL 방식으로 구현해봅시다.
PostgreSQL에서는 유저를 생성하고 `SUPERUSER` 속성을 부여하는 방식을 사용합니다.

### 1) 새로운 관리자 권한을 가진 유저 생성

`scott` 유저를 생성하고 이 유저에게 `SUPERUSER` (Oracle의 DBA 권한) 속성을 부여합니다.

```sql
-- postgres 유저(슈퍼유저)로 접속한 상태에서 실행

-- 1. 새로운 유저 scott 생성 (패스워드 지정)
CREATE ROLE scott WITH LOGIN PASSWORD 'tiger';

-- 2. scott 유저에게 슈퍼유저(SUPERUSER) 권한 부여
ALTER ROLE scott SUPERUSER;

-- (선택) scott 유저가 객체를 만들 기본 스키마를 위해 데이터베이스 생성
CREATE DATABASE scottdb OWNER scott;
```

### 2) scott 유저로 접속하여 관리자 작업 수행

이제 `scott` 유저는 최고 관리자 권한을 가지게 되었습니다. 데이터베이스 생성이나 다른 유저의 패스워드 변경 등 관리자만 할 수 있는 작업을 수행할 수 있습니다.

```bash
# scott 유저로 접속 (패스워드 'tiger' 입력)
[user@client ~]$ psql -U scott -d scottdb
Password for user scott: 

scottdb=# 
```

```sql
-- scott 계정으로 다른 일반 유저를 생성해 봅니다. (슈퍼유저이므로 가능)
CREATE ROLE adams WITH LOGIN PASSWORD 'tiger';

-- 테스트를 위한 emp, dept 테이블 생성 (일반적인 DDL)
CREATE TABLE dept (
    deptno NUMERIC(2) PRIMARY KEY,
    dname VARCHAR(14),
    loc VARCHAR(13)
);

CREATE TABLE emp (
    empno NUMERIC(4) PRIMARY KEY,
    ename VARCHAR(10),
    job VARCHAR(9),
    mgr NUMERIC(4),
    hiredate DATE,
    sal NUMERIC(7,2),
    comm NUMERIC(7,2),
    deptno NUMERIC(2) REFERENCES dept(deptno)
);

-- 데이터 입력
INSERT INTO dept VALUES (10, 'ACCOUNTING', 'NEW YORK');
INSERT INTO emp VALUES (7782, 'CLARK', 'MANAGER', 7839, '1981-06-09', 2450, NULL, 10);
```

### 3) scott의 슈퍼유저 권한 회수

보안상 일반 유저에게 관리자 권한을 주었다가 다시 회수해야 할 때가 있습니다.

```sql
-- 다시 postgres(슈퍼유저)로 접속 후 실행
-- scott 유저의 슈퍼유저 속성을 제거하고 일반 유저(NOSUPERUSER)로 강등
ALTER ROLE scott NOSUPERUSER;
```

---

## 4. Oracle 문제에 대한 PostgreSQL식 답변 및 변환 (요약)

*   **Oracle OS 보안 및 `dba` 그룹 추가:**
    *   **PostgreSQL 변환:** PostgreSQL은 OS의 `dba` 그룹 멤버십을 자동으로 관리자 권한으로 매핑하지 않습니다. `pg_hba.conf`에서 `peer` 인증을 통해 OS 유저와 DB 유저를 매핑하거나, DB 내부에서 `ALTER ROLE ... SUPERUSER;` 명령을 통해 권한을 제어합니다.
*   **Oracle OS 인증 (`sqlplus / as sysdba`):**
    *   **PostgreSQL 변환:** `pg_hba.conf`의 **Peer 인증**. 로컬 쉘에서 OS 유저명과 일치하는 DB 계정으로 비밀번호 없이 `psql`을 통해 접속합니다.
*   **Oracle Password File 인증 (원격 `sysdba` 접속):**
    *   **PostgreSQL 변환:** 별도의 `orapwd` 파일은 필요 없습니다. `pg_hba.conf`의 **패스워드 인증(md5, scram-sha-256)** 을 설정하고, `SUPERUSER` 속성을 가진 계정으로 네트워크를 통해 접속 시 비밀번호를 입력하여 인증합니다.

<aside>
💡 **핵심 요약:** PostgreSQL의 모든 인증은 **`pg_hba.conf`** 가 통제합니다. 접속 경로(로컬 소켓 vs 네트워크 IP), DB명, 유저명에 따라 어떤 인증 방식(Peer, Scram-sha-256 등)을 적용할지 세밀하게 설정할 수 있습니다.
</aside>
