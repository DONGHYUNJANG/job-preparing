# 📝  free buffer waits

## 📔 free buffer waits 완벽 정리

### 1. 개념 설명

- *`free buffer waits`*는 서버 프로세스가 데이터 파일에서 읽은 블록을 메모리(Buffer Cache)에 올리려 할 때, **Dirty Buffer(수정되었지만 아직 디스크에 기록되지 않은 블록)**가 너무 많아 빈 공간(Free Buffer)을 찾지 못해 대기하는 상태입니다.
- **동작 원리**:
    1. 서버 프로세스가 LRU 리스트를 훑으며 빈 버퍼를 찾습니다.
    2. 일정 개수(Threshold) 이상의 버퍼를 뒤졌는데도 빈 공간이 없으면 DBWR에게 "빨리 디스크에 좀 써서 공간을 만들어달라"고 요청합니다.
    3. DBWR가 공간을 만들어줄 때까지 서버 프로세스는 **`free buffer waits`** 상태로 대기합니다.

> **`buffer busy waits vs free buffer waits`**
> 
- **`buffer busy waits`**: **"특정 블록"**이 인기가 너무 많아서 줄 서는 것 (Point 경합)
- **`free buffer waits`**: **"전체 공간"**이 꽉 차서 앉을 자리가 없는 것 (Space 부족)

| 구분 | buffer busy waits | free buffer waits |
| --- | --- | --- |
| **핵심 키워드** | **"줄 서기" (점유 경합)** | **"방 없음" (공간 부족)** |
| **발생 원인** | 누군가 내가 쓰려는 블록을 이미 사용 중일 때 | Dirty Buffer가 너무 많아 새로운 블록을 올릴 빈 공간이 없을 때 |
| **주요 상황** | Hot Block(자주 쓰이는 인덱스/헤더), 빠른 커밋 | 대량의 INSERT/UPDATE, 느린 디스크 I/O, 작은 Buffer Cache |
| **비유** | 화장실 칸 앞에 줄 서 있는 상태 | 화장실 자체가 꽉 차서 입장이 안 되는 상태 |

---

## 🛠️ free buffer waits 재현 시나리오

이 이벤트는 **"메모리에 쓰여진 데이터를 디스크로 내보내는 속도(DBWR)"**가 **"메모리에 데이터를 새로 올리는 속도(Server Process)"**를 따라가지 못하게 만들면 재현됩니다.

### 1. 개념 설명 (재현 원리)

1. **DBWR의 손발을 묶습니다**: `DB_WRITER_PROCESSES`를 1로 낮추고, I/O 성능이 매우 느린 디스크 환경(또는 가상 지연)을 구성합니다.
2. **Buffer Cache를 작게 설정합니다**: 공간이 금방 차도록 `DB_CACHE_SIZE`를 최소한으로 줄입니다.
3. **엄청난 양의 데이터를 쏟아붓습니다**: `INSERT /*+ APPEND */`가 아닌, **일반 `INSERT`*를 대량으로 수행하여 Buffer Cache를 Dirty Buffer(변경되었으나 아직 디스크에 안 써진 블록)로 가득 채웁니다.
4. **결과**: 서버 프로세스는 계속 읽어오려 하지만, DBWR가 디스크로 데이터를 못 밀어내서 `Free Buffer`를 확보하지 못해 대기가 발생합니다.

### 2. 문제 해설 (재현 방법)

**[단계 1: 환경 설정]** (테스트 장비에서만 수행하세요)

- Buffer Cache 크기를 매우 작게 조정 (예: 100MB 미만)

```jsx
A. 현재 설정값 확인
먼저 현재 설정된 버퍼 캐시 크기를 확인합니다.

SQL
-- 현재 설정된 값 확인
SHOW PARAMETER db_cache_size;

-- 또는 V$ 파라미터 뷰에서 확인
SELECT name, value/1024/1024 || ' MB' as size_mb
FROM v$parameter
WHERE name = 'db_cache_size';
B. 수동으로 크기 변경 (Immediate)
free buffer waits 
재현 등을 위해 크기를 줄이거나 늘릴 때 사용합니다.

SQL
-- 메모리에 즉시 반영 (단, SGA_MAX_SIZE 범위를 넘을 수 없음)
ALTER SYSTEM SET db_cache_size = 200M;

-- 0으로 설정하면 자동 메모리 관리(ASMM)가 알아서 조절하게 됩니다.
ALTER SYSTEM SET db_cache_size = 0;
```

- DBWR 개수를 최소화 (`ALTER SYSTEM SET db_writer_processes=1 SCOPE=SPFILE;`)
- 가능하다면 테스트용 테이블스페이스를 느린 디스크(USB 등)에 배치

**[단계 2: 부하 발생]**

- 여러 개의 세션에서 동시에 대량의 `UPDATE` 또는 `INSERT`를 반복 수행합니다. (커밋은 하지 않거나 천천히 합니다.)
- 이때 **체크포인트(`CHECKPOINT`)**가 발생하지 않도록 유도하면서, 서버 프로세스가 계속해서 새로운 데이터 블록을 메모리로 로드하게 만듭니다.

---

## 🛠️ 테이블 재생성 및 데이터 벌크업

### 1. 테이블 재생성 (넉넉한 크기)

```sql
DROP TABLE big_table_a;
DROP TABLE big_table_b;

CREATE TABLE big_table_a (
    id NUMBER,
    contents VARCHAR2(2000)
);

CREATE TABLE big_table_b (
    id NUMBER,
    contents VARCHAR2(2000)
);
```

### 2. 데이터 삽입 (100만 건)

이번에는 에러 없이 들어갈 겁니다.

```sql
INSERT /*+ APPEND */ INTO big_table_a
SELECT level, RPAD('A', 1500, 'A')
FROM dual CONNECT BY level <= 1000000;
COMMIT;

INSERT /*+ APPEND */ INTO big_table_b
SELECT level, RPAD('B', 1500, 'B')
FROM dual CONNECT BY level <= 1000000;
COMMIT;
```

### 1. 세션 A: Dirty Buffer로 길막기

```sql
-- 16MB의 작은 캐시를 1500바이트짜리 Dirty 블록들로 꽉 채웁니다.
UPDATE big_table_a SET contents = RPAD('X', 1500, 'X');
-- ★ 커밋 금지! 그대로 둡니다.
```

### 2. 세션 B: 무한 SELECT + 캐시 비우기

이 코드는 루프가 돌 때마다 메모리를 강제로 비우고 디스크에서 읽어오기 때문에, 세션 A가 비워주지 않는 Dirty Buffer들 사이에서 자리를 찾느라 **`free buffer waits`**가 뜰 수밖에 없습니다.

```sql
SET TIMING ON;
BEGIN
  FOR i IN 1..100 LOOP
    -- 캐시를 비워 매번 물리적 I/O를 유도
    EXECUTE IMMEDIATE 'ALTER SYSTEM FLUSH BUFFER_CACHE';

    -- 큰 테이블 풀 스캔
    EXECUTE IMMEDIATE 'SELECT /*+ FULL(b) */ COUNT(*) FROM big_table_b b';
  END LOOP;
END;
/
```

---

## 🏗️ free buffer waits 발생 메커니즘 최종 정리

### 1. 개념 설명: 왜 대기가 발생하는가?

1. **세션 A (Dirty Buffer 제조기)**: 버퍼 캐시(16MB) 안의 모든 침대를 **'Dirty(수정 중)'** 상태로 만듭니다. 오라클은 "아직 디스크에 안 적었으니 이 침대는 절대 치우면 안 돼!"라고 잠금 장치를 겁니다.
2. **세션 B (신규 손님)**: `FLUSH` 후 `SELECT`를 하면 디스크에서 새 데이터를 가져와야 합니다. 빈 침대를 찾으려 하지만, **모든 침대가 세션 A에 의해 '치울 수 없는 상태'**로 묶여 있습니다.
3. **DBWR (청소부)의 한계**: DBWR가 어떻게든 자리를 만들려고 Dirty 블록을 디스크에 쓰기 시작하지만, 세션 B의 요구 속도보다 느립니다.
4. **결과**: 세션 B는 침대가 날 때까지 **`free buffer waits`*를 외치며 멈춰 서게 됩니다.

## 🧐 왜 그냥 읽기만 하면 안 되나요?

### 1. 개념 설명

- **Clean Buffer vs Dirty Buffer**: 단순히 `SELECT`만 해서 올라온 블록은 **'Clean Buffer'**입니다. 오라클은 공간이 부족하면 이 Clean Buffer들을 그냥 즉시 덮어씌워 버립니다(별도의 대기 없이).
- **Dirty Buffer**: 반면 `UPDATE`로 수정된 블록은 **'Dirty Buffer'**가 됩니다. 데이터 무결성을 위해 DBWR가 디스크에 기록하기 전까지는 **절대 덮어쓸 수 없습니다.**
- **결론**: 캐시를 **덮어쓸 수 없는 상태(Dirty)**로 꽉 채워놔야, 새로운 데이터를 읽으려는 세션이 "자리가 없으니 DBWR야 빨리 설거지해!"라며 `free buffer waits`를 띄우게 됩니다.

**[단계 3: 관찰]**

```sql
SELECT * FROM (
    SELECT event, total_waits, time_waited_micro, average_wait
    FROM v$system_event
    WHERE wait_class <> 'Idle' -- '가만히 쉬고 있는 놈'들은 제외
    ORDER BY time_waited_micro DESC
) WHERE ROWNUM <= 5;

SELECT
    event,
    session_id,
    COUNT(*) as wait_count
FROM v$active_session_history
WHERE sample_time > sysdate - 5/1440 -- 최근 5분
  AND event IS NOT NULL
GROUP BY event, session_id
ORDER BY wait_count DESC;

SELECT s.sid, s.serial#, s.username, s.osuser, s.program, q.sql_text
FROM v$session s
JOIN v$sql q ON s.sql_id = q.sql_id
WHERE s.sid = (위에서 찾은 세션ID);
```

- 위 쿼리를 통해 대기 이벤트가 증가하는 것을 확인할 수 있습니다.

---

> 테스트
> 

```jsx

Total System Global Area 2415917880 bytes
Fixed Size                  8899384 bytes
Variable Size             520093696 bytes
Database Buffers         1879048192 bytes
Redo Buffers                7876608 bytes
Database mounted.
Database opened.
SQL> SHOW PARAMETER db_cache_size;

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
db_cache_size                        big integer 0
SQL> ALTER SYSTEM SET db_cache_size = 10M
  2  ;

System altered.

SQL> ALTER SYSTEM SET db_writer_processes=1 SCOPE=SPFILE;

System altered.

SQL> shutdown immediate;
Database closed.
Database dismounted.
ORACLE instance shut down.
SQL>
SQL>
SQL> startup
ORACLE instance started.

Total System Global Area 2415917880 bytes
Fixed Size                  8899384 bytes
Variable Size             520093696 bytes
Database Buffers         1879048192 bytes
Redo Buffers                7876608 bytes
Database mounted.
Database opened.
SQL> show paramter db_cache_size
SP2-0158: unknown SHOW option "paramter"
SP2-0735: unknown SHOW option beginning "db_cache_s..."
SQL> show parameter db_cache_size

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
db_cache_size                        big integer 16M
SQL>

// Update에서 무한 대기로 빠짐

Elapsed: 00:00:00.00
SQL> SQL>   2    3
1000000 rows created.

Elapsed: 00:01:15.27
SQL>
Commit complete.

Elapsed: 00:00:00.00
SQL> UPDATE big_table_a SET contents = RPAD('X', 1500, 'X');

//free buffer waits 증가 
SQL> SELECT * FROM (
  2      SELECT event, total_waits, time_waited_micro, average_wait
    FROM v$system_event
    WHERE wait_class <> 'Idle' -- '가만히 쉬고 있는 놈'들은 제외
    ORDER BY time_waited_micro DESC
) WHERE ROWNUM <= 5;  3    4    5    6

EVENT                                                            TOTAL_WAITS TIME_WAITED_MICRO AVERAGE_WAIT
---------------------------------------------------------------- ----------- ----------------- ------------
free buffer waits                                                       9434         274635697         2.91
db file async I/O submit                                                 719         213470272        29.69
direct path sync                                                         465         106085049        22.81
log file parallel write                                                 1368          60355150         4.41
Data file init write                                                    4440          30775738          .69

SQL>

```

## 🏆 free buffer waits 재현 성공 분석

### 1. 개념 설명: 왜 UPDATE만으로 충분했나?

현재 `db_cache_size`를 **16MB**로 극단적으로 줄여놓으셨죠.

- **데이터의 양**: `big_table_a`의 로우 하나가 1,500바이트입니다. 8KB 블록 하나에 약 5개 정도밖에 못 들어갑니다.
- **공간 점유**: 100만 건을 수정하려고 하면, 약 20만 개의 블록이 필요합니다. 16MB 캐시에는 고작 **2,000개** 정도의 블록만 들어갈 수 있습니다.
- **현상**: `UPDATE` 세션이 데이터를 수정하기 위해 계속해서 디스크에서 블록을 읽어와야 하는데(Read for Update), 본인이 이미 수정한 Dirty Buffer들로 16MB가 순식간에 꽉 차버린 것입니다.

### 2. 문제 해설: 로그 지연보다 빨랐던 이유

보통은 로그 기록(`log file parallel write`)이 먼저 병목이 되지만, 지금은 **"메모리 통로"** 자체가 너무 좁았습니다.

1. **설거지 속도 vs 어지럽히는 속도**: `db_writer_processes=1`로 줄여놓으셨기 때문에 DBWR의 처리량은 바닥인 상태입니다.
2. **청소 불가**: 서버 프로세스는 계속해서 다음 블록을 읽어오려고 빈 버퍼를 찾는데, 캐시 안은 전부 **"아직 커밋 안 된(또는 DBWR가 안 치운) Dirty Buffer"**뿐입니다.
3. **우선순위**: 로그를 쓰기 위해 대기하기 훨씬 이전에, **"당장 다음 블록을 담을 1,500바이트의 공간"**조차 없어서 서버 프로세스가 멈춰버린 것입니다.

---

## 🚦 지난번 장애 vs 이번 실습 상황 비교

### 1. 지난번 상황: 커밋은 계속 했지만 로그가 막힘

- **상태**: `INSERT` + `COMMIT` 폭주 + **Log Switch(Archiving)** 지연.
- **메커니즘**:
    1. 커밋을 했으니 Oracle은 데이터를 디스크에 쓸 준비(`Dirty`)가 되었습니다.
    2. 하지만 로그 파일이 꽉 차서 `LGWR`가 멈추자, `DBWR`도 "로그를 먼저 써야 데이터를 쓸 수 있다"는 원칙 때문에 멈췄습니다.
    3. 이 과정에서 프로세스들이 **세그먼트 헤더나 특정 블록**을 점유(Pin)한 채로 로그가 풀리길 기다리며 멈춰버렸습니다.
- **결과**: 공간이 부족해지기 전에 **통로(Block)**를 잡고 안 놔주는 경합이 먼저 터져서 **`buffer busy waits`*가 지배적이었던 것입니다.

### 2. 이번 실습: 커밋 없이 버퍼를 강제로 점령

- **상태**: 대량 `UPDATE` + **COMMIT 안 함** + 극단적으로 작은 버퍼(16MB).
- **메커니즘**:
    1. 커밋을 안 하니 모든 버퍼가 "수정 중"인 상태로 묶여버립니다.
    2. `DBWR`가 자리를 만들려고 해도, 아직 확정되지 않은 데이터들이라 함부로 치우기가 매우 어렵습니다.
    3. 16MB라는 아주 좁은 공간이 순식간에 **'수정 중인 방'**으로 꽉 찼습니다.
    4. 새로운 데이터를 읽어올 공간이 ** 물리적으로 0**이 되었습니다.
- **결과**: 다른 경합을 따질 것도 없이 **"앉을 자리(Free Buffer) 자체가 없다"**는 비명이 가장 먼저 터져 나온 것입니다.

---

## 📝 문제 해설 (요약)

| **구분** | **지난번 (Log/Busy 중심)** | **이번 실습 (Free Buffer 중심)** |
| --- | --- | --- |
| **핵심 원인** | 로그 기록 불가로 인한 **프로세스 정지** | 공간 부족으로 인한 **입장 불가** |
| **버퍼 상태** | 기록 대기 중인 블록들 | 수정 중이라 버릴 수 없는 블록들 |
| **주요 대기** | `buffer busy waits`, `log file sync` | **`free buffer waits`** |