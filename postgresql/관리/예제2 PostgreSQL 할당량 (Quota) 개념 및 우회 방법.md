# 예제2. PostgreSQL 할당량 (Quota) 개념 및 우회 방법

PostgreSQL은 Oracle과 같이 유저별로 특정 테이블스페이스에 대한 **물리적인 디스크 사용량(Quota)을 직접적으로 제한하는 내장 기능(Native Feature)을 제공하지 않습니다.**
Oracle에서는 `ALTER USER scott QUOTA 20M ON users;` 와 같이 설정하지만, PostgreSQL에서는 다른 방식을 통해 자원을 통제해야 합니다.

## 1. Oracle과 PostgreSQL의 차이점

| 특징 | Oracle | PostgreSQL |
| --- | --- | --- |
| **테이블스페이스 할당량(Quota)** | 제공함 (`ALTER USER ... QUOTA ...`) | **제공하지 않음** (별도 확장 모듈이나 OS 기능 필요) |
| **테이블스페이스 권한** | Quota가 있어야 객체 생성 가능 | `GRANT CREATE ON TABLESPACE` 권한만 있으면 무한정 생성 가능 |
| **자원 통제 주체** | DBMS 내부 기능 | OS 레벨 디스크 할당량 또는 서드파티 확장(diskquota 등) |
|  |  |  |

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

### 4. 논리적 vs 물리적 분리의 차이

- **논리적 분리만 할 경우:** 하나의 물리 디스크(RAID 그룹 등) 위에 여러 테이블스페이스를 만들고 각각 다른 디스크 경로처럼 보이게만 해봤자, 결국 물리적인 헤드와 컨트롤러는 하나입니다. 이 경우 핫블럭(I/O 경합) 해소 효과는 **0**에 가깝습니다.
- **물리적 분리를 할 경우:** 테이블 A는 SSD 1번(TS_A), 테이블 B는 SSD 2번(TS_B)으로 물리적 저장 장치를 완전히 떼어놓는다면, 서로 다른 컨트롤러와 대역폭을 사용하므로 **I/O 경합이 획기적으로 줄어듭니다.**

### 5. 오라클에서의 관점

오라클에서도 전통적으로 고성능 DB를 설계할 때 **"I/O Balancing"**을 위해 테이블스페이스별로 디스크를 분리했습니다.

- **일반적인 방식:** 인덱스 전용 테이블스페이스와 데이터 전용 테이블스페이스를 분리하여 서로 다른 디스크에 배치합니다. (인덱스 스캔과 테이블 액세스가 동시에 일어날 때 I/O 분산 유도)
- **핫블럭 예방:** 특정 테이블에 트랜잭션이 몰릴 때 해당 테이블을 별도의 물리 디스크에 있는 테이블스페이스로 옮기면 전체 시스템의 Wait Event가 줄어듭니다.

### 6. PostgreSQL에서의 관점

PostgreSQL에서도 원리는 동일합니다. 하지만 Postgres만의 특징이 있습니다.

- **설계 방식:** Postgres는 디렉토리 기반의 테이블스페이스를 사용하므로, OS에서 서로 다른 물리 마운트 포인트(예: `/data/disk1`, `/data/disk2`)를 잡고 각각 테이블스페이스를 생성하면 됩니다.
- **핫블럭 해소 효과:** * **임시 파일 분리:** 앞서 언급한 `temp_tablespaces`를 별도의 고성능 디스크로 빼는 것이 가장 일반적이고 효과가 큽니다.
    - **VACUUM 부하 분산:** Postgres의 특징인 VACUUM 작업은 I/O를 많이 먹습니다. 빈번하게 업데이트되는 테이블을 별도 디스크의 테이블스페이스로 빼두면, VACUUM이 돌 때 운영 데이터가 있는 디스크의 I/O 응답 속도 저하를 막을 수 있습니다.

---

### 7. 실무에서 정말 테이블별로 다 나누나? (일반적인가?)

**모든 테이블을 다 나누지는 않습니다.** 관리 포인트가 너무 늘어나기 때문입니다. 실무에서는 보통 다음과 같은 기준을 따릅니다.

1. **I/O 집중도에 따른 분리 (80/20 법칙):** 전체 데이터의 20%에 해당하는 핵심 테이블(트랜잭션이 집중되는 테이블)만 별도의 고성능 물리 디스크(NVMe 등) 테이블스페이스로 뺍니다.
2. **데이터 성격에 따른 분리:**
    - **Active 데이터:** 빠른 디스크 (SSD)
    - **Archive/History 데이터:** 느리고 싼 디스크 (HDD)
3. **로그 및 임시 공간:** WAL(Write Ahead Log) 파일과 Temp 공간은 데이터와 물리적으로 다른 디스크에 두는 것이 국룰(Best Practice)입니다.

---