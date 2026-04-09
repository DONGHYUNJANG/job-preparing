# PostgreSQL 학습 자료: 오라클(Oracle) 사용자 관점에서의 비교 및 실습

본 자료는 오라클(Oracle) 환경에 익숙한 사용자가 PostgreSQL의 사용자 및 스키마 관리, 보안 정책 등을 학습할 수 있도록 작성되었습니다. 요청하신 내용에 맞춰 PostgreSQL 환경의 특성과 오라클과의 차이점을 중심으로 설명하며, 실습과 예제를 포함합니다. (예제는 가능한 한 전통적인 `scott` 스키마 환경을 가정하여 설명합니다.)

---

## 1. 주요 항목별 개념 설명

### 1. 고유 Username
*   **Oracle**: 데이터베이스 내에 고유한 `USER`를 생성합니다. `USER`는 곧 `SCHEMA`와 동일한 개념을 가집니다.
*   **PostgreSQL**: PostgreSQL에서는 사용자(User)와 그룹(Group)을 통합하여 **Role(역할)**이라는 개념을 사용합니다. `CREATE USER`는 `CREATE ROLE ... LOGIN`과 동일한 명령어입니다. Role은 데이터베이스 클러스터(인스턴스) 전체에서 고유하며, 여러 데이터베이스에 접근할 수 있습니다.

### 2. 인증 방식 (Authentication)
*   **Oracle**: 주로 데이터베이스 내장 비밀번호 인증(`IDENTIFIED BY password`)이나 외부(OS) 인증을 사용합니다.
*   **PostgreSQL**: 사용자를 생성할 때 비밀번호를 지정할 수 있지만(`PASSWORD 'password'`), 실제 인증 방식은 서버의 설정 파일인 **`pg_hba.conf`** 파일에 의해 통제됩니다. 여기에서 패스워드 인증(scram-sha-256, md5), OS 인증(peer, ident), 신뢰 인증(trust) 등을 클라이언트 IP 대역별로 상세하게 설정합니다.

### 3. 기본 테이블스페이스 (Default Tablespace)
*   **Oracle**: 유저를 생성할 때 `DEFAULT TABLESPACE` 구문으로 할당하며, 해당 유저가 생성하는 객체는 명시하지 않으면 이 공간에 저장됩니다.
*   **PostgreSQL**: 데이터베이스 자체에 기본 테이블스페이스가 지정됩니다. 특정 Role(유저)에게 기본 테이블스페이스를 할당하려면, Role의 설정(Parameter)을 변경하는 방식을 사용합니다.
    *   `ALTER ROLE username SET default_tablespace = 'tablespace_name';`

### 4. 임시 테이블스페이스 (Temporary Tablespace)
*   **Oracle**: 정렬이나 임시 데이터를 위해 유저별로 `TEMPORARY TABLESPACE`를 할당합니다.
*   **PostgreSQL**: `temp_tablespaces` 파라미터를 통해 세션이나 Role 단위로 임시 테이블스페이스를 지정할 수 있습니다.
    *   `ALTER ROLE username SET temp_tablespaces = 'temp_ts_name';`

### 5. 유저 프로파일 (Profile)
*   **Oracle**: 패스워드 정책(만료, 재사용 제한 등)과 리소스 제한(CPU, 세션 수 등)을 `PROFILE` 객체로 묶어 유저에게 할당합니다.
*   **PostgreSQL**: 오라클과 같은 형태의 독립된 `Profile` 객체는 없습니다. 대신 다음과 같이 개별적으로 제어합니다.
    *   **리소스 제한**: `ALTER ROLE username CONNECTION LIMIT 10;`, `statement_timeout` 등 Role 속성 설정.
    *   **패스워드 정책**: 패스워드 만료일은 `VALID UNTIL` 구문으로 지정할 수 있습니다. (예: `VALID UNTIL '2025-01-01'`). 복잡도 등의 강력한 통제는 `passwordcheck` 확장 모듈이나 OS 수준의 인증(PAM)을 연동하여 해결합니다.

### 6. 초기 Consumer Group
*   **Oracle**: Oracle Database Resource Manager(DBRM)를 사용하여 유저별로 CPU, I/O 자원을 할당하는 그룹입니다.
*   **PostgreSQL**: 내장된 자원 관리자(Resource Manager)나 Consumer Group과 정확히 일치하는 기능은 없습니다. OS 수준의 **cgroups**를 활용하여 프로세스별 자원을 통제하거나, 연결 풀링 도구인 **pgBouncer** 등을 사용하여 세션/연결 수를 제어하는 방식으로 우회하여 구현합니다.

### 7. 계정 상태 (Account Status)
*   **Oracle**: 계정을 `OPEN`, `LOCKED`, `EXPIRED` 상태로 관리합니다 (`ALTER USER username ACCOUNT LOCK;`).
*   **PostgreSQL**: 명시적인 LOCK 명령어 대신 로그인 권한을 뺏거나 연결을 막는 방식을 사용합니다.
    *   **Lock (잠금)**: `ALTER ROLE username NOLOGIN;` 또는 `ALTER ROLE username CONNECTION LIMIT 0;`
    *   **Unlock (해제)**: `ALTER ROLE username LOGIN;`

### 8. 스키마 (Schema)
*   **Oracle**: 유저 생성 시 유저 이름과 동일한 스키마가 1:1로 자동 생성됩니다.
*   **PostgreSQL**: **유저(Role)와 스키마(Schema)는 분리된 개념**입니다. 스키마는 데이터베이스 내의 네임스페이스(논리적 디렉토리)입니다. 한 유저가 여러 스키마를 소유할 수도 있고, 다른 유저의 스키마에 권한을 받아 접근할 수도 있습니다. 기본적으로 모든 유저는 `public` 이라는 공용 스키마에 객체를 생성하게 됩니다. (오라클처럼 유저명과 동일한 스키마를 생성하고 `search_path`를 설정해주는 방식을 권장합니다.)

---

## 2. 실습 및 문제 풀이

*(참고: 테이블스페이스 실습을 위해서는 OS 상에 실제 디렉토리가 존재하고, postgres 유저의 쓰기 권한이 있어야 합니다. 본 실습에서는 개념적 명령어 위주로 설명합니다.)*

### 실습 1. 유저 생성하기

가장 기본적인 형태의 데이터베이스 로그인 가능한 유저를 생성합니다.

```sql
-- 'scott'이라는 유저를 'tiger'라는 패스워드로 생성
CREATE USER scott WITH PASSWORD 'tiger';

-- 데이터베이스 접속 후 emp, dept 테이블이 있는 스키마(예: public 스키마)에 접근하기 위해 권한 부여 필요
-- GRANT SELECT ON emp, dept TO scott;
```

### 실습 2. OS 인증 방법으로 유저 생성

PostgreSQL에서 OS 인증을 사용하려면 데이터베이스 내에는 패스워드 없는 Role을 생성하고, 서버의 `pg_hba.conf` 파일에서 인증 방식을 `peer` 또는 `ident`로 설정해야 합니다.

```sql
-- 1. DB 내에 패스워드 없이 로그인 가능한 Role 생성
-- (주의: OS에 존재하는 유저 계정명과 동일해야 함)
CREATE ROLE os_user_test LOGIN;
```
> **설정 설명 (`pg_hba.conf`)**:
> 서버 내부 설정 파일(`pg_hba.conf`)에 다음과 같이 `peer` 인증이 설정되어 있어야, 리눅스/유닉스 터미널에서 `os_user_test` OS 계정으로 로그인한 상태에서 패스워드 없이 DB 접속(`psql`)이 가능합니다.
> `local   all             all                                     peer`

### 실습 3. 기본(Default) 테이블스페이스와 임시(Temp) 테이블스페이스 사용하기

테이블스페이스를 생성한 후, 유저(Role)에게 기본값으로 설정하는 방법입니다.

```sql
-- (선행 작업) 테이블스페이스 생성 (경로는 OS 환경에 맞게 지정해야 함)
-- CREATE TABLESPACE ts_users LOCATION '/var/lib/postgresql/data/users';
-- CREATE TABLESPACE ts_temp LOCATION '/var/lib/postgresql/data/temp';

-- 특정 유저(scott)의 세션에만 적용할 기본 테이블스페이스 설정
ALTER ROLE scott SET default_tablespace = 'ts_users';

-- 특정 유저(scott)의 세션에만 적용할 임시 테이블스페이스 설정
ALTER ROLE scott SET temp_tablespaces = 'ts_temp';
```

### 문제 1. allen 유저 생성 및 테이블스페이스 할당

> **문제:** allen 이라는 유저를 생성하는데 allen 유저의 default 테이블 스페이스가 users 가 되게하고 임시 테이블 스페이스는 temp 가 되게 하시오.

**해결 방법 (PostgreSQL 방식):**
(전제조건: 데이터베이스 내에 `users`와 `temp`라는 이름의 테이블스페이스가 이미 생성되어 있다고 가정합니다.)

```sql
-- 1. allen 유저 생성 (로그인 가능하도록 PASSWORD 지정)
CREATE USER allen WITH PASSWORD 'allen_password';

-- 2. allen 유저의 기본 객체 생성 공간을 users 테이블스페이스로 지정
ALTER ROLE allen SET default_tablespace = 'users';

-- 3. allen 유저의 정렬 등 임시 작업 공간을 temp 테이블스페이스로 지정
ALTER ROLE allen SET temp_tablespaces = 'temp';

-- (확인) 설정이 잘 되었는지 확인
-- psql 명령창에서 \drds allen 을 입력하거나 아래 쿼리 실행
-- SELECT rolname, rolconfig FROM pg_roles WHERE rolname = 'allen';
```
