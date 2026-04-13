# PostgreSQL 할당량 (Quota) 개념 및 우회 방법

PostgreSQL은 Oracle과 같이 유저별로 특정 테이블스페이스에 대한 **물리적인 디스크 사용량(Quota)을 직접적으로 제한하는 내장 기능(Native Feature)을 제공하지 않습니다.** 
Oracle에서는 `ALTER USER scott QUOTA 20M ON users;` 와 같이 설정하지만, PostgreSQL에서는 다른 방식을 통해 자원을 통제해야 합니다.

## 1. Oracle과 PostgreSQL의 차이점

| 특징 | Oracle | PostgreSQL |
| --- | --- | --- |
| **테이블스페이스 할당량(Quota)** | 제공함 (`ALTER USER ... QUOTA ...`) | **제공하지 않음** (별도 확장 모듈이나 OS 기능 필요) |
| **테이블스페이스 권한** | Quota가 있어야 객체 생성 가능 | `GRANT CREATE ON TABLESPACE` 권한만 있으면 무한정 생성 가능 |
| **자원 통제 주체** | DBMS 내부 기능 | OS 레벨 디스크 할당량 또는 서드파티 확장(diskquota 등) |

## 2. PostgreSQL에서 유사하게 자원을 통제하는 방법

PostgreSQL에서 특정 유저가 디스크 공간을 무한정 사용하는 것을 방지하기 위해 다음과 같은 대안을 사용할 수 있습니다.

### 대안 1: 테이블스페이스 생성 권한(`CREATE`) 제어
가장 기본적인 방법은 일반 유저에게 특정 테이블스페이스에 객체를 생성할 수 있는 권한 자체를 주지 않거나, 필요한 경우에만 부여하는 것입니다.

```sql
-- 1. 새로운 테이블스페이스 생성 (postgres 슈퍼유저로 실행, 실제 존재하는 디렉토리 필요)
CREATE TABLESPACE ts_users LOCATION '/var/lib/postgresql/data/ts_users';

-- 2. scott 유저(역할) 생성
CREATE ROLE scott WITH LOGIN PASSWORD 'tiger';

-- 3. scott 유저에게 ts_users 테이블스페이스에 객체를 생성할 권한 부여
GRANT CREATE ON TABLESPACE ts_users TO scott;

-- 4. 권한 회수 (더 이상 해당 테이블스페이스를 사용하지 못하게 함, 기존 데이터는 유지됨)
REVOKE CREATE ON TABLESPACE ts_users FROM scott;
```

### 대안 2: 임시 파일 사용량 제한 (temp_file_limit)
디스크 용량 제한은 아니지만, 정렬(ORDER BY)이나 해시 조인 등에 사용되는 임시 파일의 최대 크기를 제한하여 디스크 고갈을 방지할 수 있습니다.
```sql
-- 세션 당 사용할 수 있는 임시 파일의 최대 크기를 10MB로 제한 (KB 단위)
ALTER ROLE scott SET temp_file_limit = 10240;
```

### 대안 3: 유저(Role)의 연결 수 제한 (Connection Limit)
유저가 시스템 자원을 과도하게 사용하는 것을 막기 위해 동시 접속 수를 제한할 수 있습니다.
```sql
-- scott 유저의 최대 동시 접속 수를 5개로 제한
ALTER ROLE scott CONNECTION LIMIT 5;
```

---

## 3. 실습: PostgreSQL에서의 테이블스페이스 및 권한 제어

Oracle의 실습과 유사하게, 유저를 생성하고 테이블스페이스에 데이터를 넣는 과정을 PostgreSQL 방식으로 진행해봅니다. (Quota 제한이 없으므로 권한 제어로 대체합니다.)

### 1) 일반 유저 생성 및 권한 부여

```sql
-- 슈퍼유저(postgres)로 접속하여 실행
-- jack 유저 생성
CREATE ROLE jack WITH LOGIN PASSWORD 'tiger';

-- 기본 데이터베이스 접속 권한 부여 (예: postgres DB)
GRANT CONNECT ON DATABASE postgres TO jack;

-- 기본 스키마(public)에 테이블 생성 권한 부여
GRANT CREATE ON SCHEMA public TO jack;
```

### 2) jack 유저로 접속하여 테이블 생성 및 데이터 입력

```sql
-- jack 유저로 접속 후 실행
CREATE TABLE emp90 (
    empno NUMERIC(10),
    ename VARCHAR(20),
    sal NUMERIC(10)
);

-- 기본 공간에 생성됨
INSERT INTO emp90 VALUES (1111, 'scott', 3000);
```

### 3) 새로운 테이블스페이스 생성 및 jack에게 권한 부여

```sql
-- 슈퍼유저(postgres)로 접속하여 실행
-- OS상에 해당 디렉토리가 존재하고 postgres 유저에게 권한이 있어야 함
CREATE TABLESPACE ts_users LOCATION '/tmp/pg_ts_users';

-- jack 유저에게 ts_users 테이블스페이스 사용 권한 부여
GRANT CREATE ON TABLESPACE ts_users TO jack;
```

### 4) jack 유저로 특정 테이블스페이스에 테이블 생성 및 대량 데이터 입력

```sql
-- jack 유저로 접속 후 실행
-- ts_users 테이블스페이스에 새로운 테이블 생성
CREATE TABLE emp90_ts (
    empno NUMERIC(10),
    ename VARCHAR(20),
    sal NUMERIC(10)
) TABLESPACE ts_users;

INSERT INTO emp90_ts VALUES (1111, 'scott', 3000);

-- Oracle과 같이 데이터를 기하급수적으로 증가시키는 쿼리 (PostgreSQL 방식)
INSERT INTO emp90_ts SELECT * FROM emp90_ts;
INSERT INTO emp90_ts SELECT * FROM emp90_ts;
INSERT INTO emp90_ts SELECT * FROM emp90_ts;
-- ... 계속 실행

-- 💡 결과: PostgreSQL은 Quota 설정이 없으므로, OS 디스크가 가득 차기 전까지는 
-- ORA-01536 (space quota exceeded) 같은 논리적인 쿼터 에러가 발생하지 않습니다.
-- 디스크가 가득 차면 "No space left on device" (OS 레벨 에러)가 발생합니다.
```

### 5) jack 유저의 테이블스페이스 사용 권한 회수

디스크 공간을 너무 많이 사용하는 것을 방지하기 위해 객체 생성 권한을 뺏을 수 있습니다.

```sql
-- 슈퍼유저(postgres)로 접속하여 실행
REVOKE CREATE ON TABLESPACE ts_users FROM jack;
```

> **💡 주의:** `REVOKE CREATE`를 하더라도 이미 `ts_users`에 생성된 `emp90_ts` 테이블의 데이터 조회(SELECT)나 추가(INSERT)는 막히지 않습니다. 새로운 테이블이나 인덱스를 해당 테이블스페이스에 생성하는 것만 차단됩니다. 
> 데이터 추가 자체를 막으려면 해당 테이블에 대한 `INSERT` 권한을 회수하거나 읽기 전용으로 만들어야 합니다.

---

## 4. Oracle 문제에 대한 PostgreSQL식 답변 및 변환

**문제1. jack 에게서 unlimited tablespace 권한을 취소하시오**
- **PostgreSQL:** `UNLIMITED TABLESPACE` 라는 시스템 권한이 존재하지 않습니다. 객체 생성을 막기 위해 테이블스페이스 단위로 `CREATE` 권한을 회수합니다.
  ```sql
  REVOKE CREATE ON TABLESPACE ts_users FROM jack;
  ```

**문제2. ts7000 이라는 테이블 스페이스를 사이즈 100m 로 생성하시오**
- **PostgreSQL:** 테이블스페이스 생성 시 DBMS 레벨에서 사이즈를 지정할 수 없습니다. 크기를 제한하려면 OS 레벨에서 `/tmp/ts7000` 디렉토리에 100M 단위의 파일 시스템 쿼터를 설정한 후 테이블스페이스를 생성해야 합니다.
  ```sql
  CREATE TABLESPACE ts7000 LOCATION '/tmp/ts7000';
  ```

**문제3. jack 이 ts7000 테이블 스페이스를 50m 만 사용하도록 쿼터를 설정하시오**
- **PostgreSQL:** 내장된 Quota 기능이 없습니다. 앞서 언급한 OS 레벨 파티션 할당량을 사용하거나 `diskquota` 같은 서드파티 확장을 설치하여 구성해야 합니다.

**문제4. jack 으로 접속해서 ts7000 에 테이블을 임의로 생성하고 데이터를 입력해서 쿼터 부족 오류가 날때까지 입력하시오**
- **PostgreSQL:** 내장 Quota가 없으므로 물리적 디스크가 가득 찰 때까지 입력됩니다. 가득 차게 되면 PostgreSQL 자체 에러가 아닌, OS 레벨의 `No space left on device` 에러가 발생하며 트랜잭션이 롤백됩니다.

**문제5. jack 유저가 temp 테이블 스페이스의 쿼터를 10m 만 쓸 수 있도록 제한하시오**
- **PostgreSQL:** 임시 파일 용량 제한은 `temp_file_limit` 파라미터로 설정 가능합니다. 세션당 생성할 수 있는 임시 파일의 최대 크기를 제한합니다.
  ```sql
  -- jack 유저의 임시 파일 사용 한도를 10MB(10240KB)로 제한
  ALTER ROLE jack SET temp_file_limit = 10240;
  ```

**문제6. jack 유저가 undotbs2 테이블 스페이스의 쿼터를 10m 만 쓸 수 있도록 제한하시오**
- **PostgreSQL:** PostgreSQL은 Oracle의 UNDO 세그먼트 대신 **MVCC(다중 버전 동시성 제어)** 아키텍처를 사용하여 테이블 내에 이전 버전 데이터를 직접 보관합니다. 따라서 별도의 Undo 테이블스페이스가 존재하지 않으며, 이와 관련된 Quota 설정도 없습니다. (대신 `VACUUM` 메커니즘을 통해 불필요해진 공간을 회수합니다.)

**문제7. jack2 라는 유저를 만들고 connect 와 resource 라는 롤을 부여하면 jack2 에게 unlimited tablespace 권한이 자동으로 들어가는지 확인하시오**
- **PostgreSQL:** Oracle과 같은 내장 `CONNECT`, `RESOURCE` 롤은 기본적으로 제공되지 않습니다. (권한 부여용 스크립트로 만들 수는 있으나 기본 내장이 아님). 또한 `UNLIMITED TABLESPACE` 권한의 개념이 없기 때문에, 객체를 생성할 테이블스페이스에 대해 명시적으로 `GRANT CREATE ON TABLESPACE ...` 를 실행해주어야 합니다.
