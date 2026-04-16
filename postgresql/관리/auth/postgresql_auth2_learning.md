# PostgreSQL 권한 관리 및 최소 권한의 원칙 (Principle of Least Privilege)

Oracle의 권한 관리 방식과 PostgreSQL의 권한 관리 방식을 비교하며, PostgreSQL 환경에서 최소 권한의 원칙을 적용하는 방법과 예제를 설명합니다.

## 항목별 상세 설명 (Oracle vs PostgreSQL)

### 1) 데이터 딕셔너리 보호
* **Oracle (`O7_DICTIONARY_ACCESSIBILITY`)**: SYS 소유의 딕셔너리에 대한 접근을 통제하는 파라미터를 제공합니다.
* **PostgreSQL (시스템 카탈로그 보호)**: 시스템 카탈로그(`pg_catalog` 스키마)가 데이터 딕셔너리 역할을 합니다. PostgreSQL은 기본적으로 대부분의 시스템 뷰(예: `pg_tables`, `pg_class`)를 모든 사용자(`PUBLIC`)가 조회할 수 있도록 허용합니다.
다만, 보안에 민감한 정보(예: 비밀번호 해시가 포함된 `pg_authid`)는 일반 사용자가 조회할 수 없도록 원천적으로 격리되어 있습니다. 특정 카탈로그의 뷰를 막기보다는 세션 통계를 분리하는 식으로 최소 권한을 유지합니다.

**적용 예제**:
일반 유저는 자신의 세션 정보만 볼 수 있으며, 다른 유저의 세션 상태를 보려면 명시적으로 권한을 부여받아야 합니다.
```sql
-- scott 유저 생성
CREATE ROLE scott LOGIN PASSWORD 'tiger';

-- 다른 세션의 쿼리 및 상태를 볼 수 있는 권한을 부여/회수하는 예제
GRANT pg_read_all_stats TO scott;
REVOKE pg_read_all_stats FROM scott;
```

### 2) PUBLIC 권한 정리
* **Oracle**: `PUBLIC` 그룹에 불필요하게 부여된 패키지 실행 권한(예: UTL_FILE) 등을 회수하여 권한을 최소화합니다.
* **PostgreSQL**: `PUBLIC`은 모든 사용자가 암묵적으로 속하는 가상의 역할(Role)입니다. 
PostgreSQL 14 버전까지는 `public` 스키마에 대해 누구나 테이블 등을 생성(`CREATE`)할 수 있었으나, **PostgreSQL 15부터는 보안 강화를 위해 `PUBLIC` 역할에서 `CREATE` 권한이 기본적으로 제거**되었습니다.
또한, 함수(Function) 생성 시 기본적으로 `PUBLIC`에게 실행(`EXECUTE`) 권한이 부여되므로 민감한 함수의 경우 이 권한을 회수해야 합니다.

**적용 예제**:
```sql
-- 특정 함수에 대한 PUBLIC의 실행 권한 회수 (최소 권한 원칙)
CREATE FUNCTION get_sensitive_data() RETURNS text AS $$
BEGIN
    RETURN 'Secret Data';
END;
$$ LANGUAGE plpgsql;

-- 생성된 함수는 PUBLIC이 실행 가능하므로 권한을 회수합니다.
REVOKE EXECUTE ON FUNCTION get_sensitive_data() FROM PUBLIC;

-- 업무상 필요한 특정 유저(scott)에게만 권한 부여
GRANT EXECUTE ON FUNCTION get_sensitive_data() TO scott;
```

### 3) 디렉토리 접근 제한
* **Oracle**: `DIRECTORY` 객체를 생성하고 특정 유저에게 READ/WRITE 권한을 부여합니다.
* **PostgreSQL**: Oracle처럼 DB 내부에 독립된 디렉토리 객체를 생성하지 않습니다. 대신 `COPY` 명령 등을 통해 OS 서버 파일에 직접 접근할 때 권한을 제어합니다. 과거에는 최고 관리자(`superuser`)만 파일 접근이 가능했지만, 현재는 `pg_read_server_files` 등의 시스템 역할을 통해 권한을 분리할 수 있습니다.

**적용 예제**:
```sql
-- scott 유저에게 서버의 파일을 읽을 수 있는 권한만 제한적으로 부여
GRANT pg_read_server_files TO scott;

-- 불필요해진 파일 읽기 권한 회수
REVOKE pg_read_server_files FROM scott;
```

### 4) 관리 권한(DBA Role 등) 최소화
* **Oracle**: DBA Role (200개 이상의 권한 묶음) 대신 개별 권한 부여를 권장합니다.
* **PostgreSQL**: 최고 관리자인 `superuser` 역할은 시스템의 모든 권한 체크를 무시하므로 절대로 일반 유저나 애플리케이션 계정에 부여해서는 안 됩니다. 대신 역할을 잘게 쪼개어 필요한 권한만 부여해야 합니다. (PostgreSQL 14부터 제공되는 읽기 전용, 쓰기 전용 기본 역할 활용)

**적용 예제**:
```sql
-- 1. 개발자 유저 생성
CREATE ROLE dev_user LOGIN PASSWORD 'dev123';

-- 2. DB 접속 권한 및 스키마 사용 권한 부여
GRANT CONNECT ON DATABASE postgres TO dev_user;
GRANT USAGE ON SCHEMA public TO dev_user;

-- 3. superuser 대신 DB 내 모든 테이블의 읽기 권한만 부여 (PostgreSQL 14+)
GRANT pg_read_all_data TO dev_user;

-- 4. 또는 특정 테이블에 대해서만 권한 부여 (가장 권장되는 최소 권한 원칙)
GRANT SELECT, INSERT ON emp TO dev_user;
```

### 5) 원격 OS 인증 차단
* **Oracle**: `REMOTE_OS_AUTHENT = FALSE` 설정을 통해 원격 OS 인증을 차단합니다.
* **PostgreSQL**: DB 파라미터가 아닌 클라이언트 인증 설정 파일인 **`pg_hba.conf`** 에서 통제합니다. 접속자의 IP나 OS 계정을 검증 없이 무조건 신뢰하는 `trust` 방식이나 원격 `ident` 방식은 치명적인 보안 취약점이 될 수 있으므로, 반드시 패스워드 기반의 강력한 인증 방식을 사용해야 합니다.

**적용 예제 (`pg_hba.conf` 파일 수정)**:
```text
# [위험] IP만 맞으면 비밀번호 없이 접속을 허용하는 설정 (사용 금지)
# host    all             all             0.0.0.0/0               trust

# [권장] 강력한 해시 알고리즘(SCRAM-SHA-256) 기반의 비밀번호 인증만 허용
# TYPE  DATABASE        USER            ADDRESS                 METHOD
host    all             all             0.0.0.0/0               scram-sha-256
```
설정을 변경한 후에는 변경사항을 적용하기 위해 설정 파일을 리로드해야 합니다.
```sql
-- 관리자 계정에서 실행
SELECT pg_reload_conf();
```

---

## 실습: 권한의 분리와 격리 (Oracle 실습 변형)

Oracle의 `O7_DICTIONARY_ACCESSIBILITY` 파라미터를 끄고 켜는 실습은 PostgreSQL의 아키텍처와는 맞지 않습니다. PostgreSQL에서는 카탈로그를 막는 대신 **스키마(Schema)와 객체 권한(GRANT/REVOKE)**을 이용해 유저 간의 데이터를 완벽하게 격리하는 방식으로 보안을 테스트합니다.

이 실습에서는 `scott`이 생성한 객체를 `smith`가 권한 없이 접근할 때 어떻게 차단되는지, 그리고 최소 권한을 부여했을 때 어떻게 동작하는지 확인합니다.

```sql
-- [관리자(postgres) 세션]
-- 1. scott 유저 및 전용 스키마 준비
CREATE ROLE scott LOGIN PASSWORD 'tiger';
CREATE SCHEMA AUTHORIZATION scott; 

-- scott 세션으로 전환 (가상으로 세션 변경)
SET ROLE scott;

-- scott 스키마에 dept 테이블 생성 및 데이터 삽입
CREATE TABLE dept (
    deptno INT PRIMARY KEY,
    dname VARCHAR(14),
    loc VARCHAR(13)
);
INSERT INTO dept VALUES (10, 'ACCOUNTING', 'NEW YORK');
INSERT INTO dept VALUES (20, 'RESEARCH', 'DALLAS');
INSERT INTO dept VALUES (30, 'SALES', 'CHICAGO');
INSERT INTO dept VALUES (40, 'OPERATIONS', 'BOSTON');

-- 다시 관리자로 복귀
RESET ROLE; 


-- 2. smith 유저 생성 및 DB 접속 권한 부여
CREATE ROLE smith LOGIN PASSWORD 'tiger';
GRANT CONNECT ON DATABASE postgres TO smith;


-- [smith 세션]
-- smith 세션으로 전환 (psql 터미널 기준: \c postgres smith)
SET ROLE smith;

-- 시스템 카탈로그 뷰는 기본적으로 조회가 가능함 (PostgreSQL의 정상 동작)
SELECT tablename FROM pg_tables WHERE schemaname = 'pg_catalog' LIMIT 5;

-- 권한이 없는 scott의 dept 테이블 조회 시도 -> 실패 (권한 차단)
SELECT * FROM scott.dept;
-- ERROR: permission denied for schema scott

RESET ROLE;


-- [관리자 또는 scott 세션]
-- 3. smith에게 scott의 dept 테이블 읽기 권한을 명시적으로 부여 (최소 권한)
-- 스키마 사용 권한(USAGE)과 테이블 조회 권한(SELECT)을 모두 주어야 합니다.
GRANT USAGE ON SCHEMA scott TO smith;
GRANT SELECT ON scott.dept TO smith;


-- [smith 세션]
SET ROLE smith;

-- 4. 최소 권한을 부여받은 후 테이블 조회 -> 성공
SELECT * FROM scott.dept;

/* 결과:
 deptno |   dname    |   loc    
--------+------------+----------
     10 | ACCOUNTING | NEW YORK
     20 | RESEARCH   | DALLAS
     30 | SALES      | CHICAGO
     40 | OPERATIONS | BOSTON
*/

-- 다른 동작(예: INSERT, UPDATE)을 시도하면 여전히 차단됩니다. (최소 권한의 원칙 유지)
INSERT INTO scott.dept VALUES (50, 'IT', 'SEOUL');
-- ERROR: permission denied for table dept
```
