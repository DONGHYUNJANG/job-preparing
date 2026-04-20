# direct path read/wirte

---

### 1. 실무에서 가장 흔한 케이스: SQL Work Area (PGA) 부족

실무에서는 SGA가 작아서 발생하는 DPR보다, **정렬(Sort)이나 해시 조인(Hash Join) 시 PGA가 부족해서** 발생하는 DPR이 훨씬 치명적입니다.

- **메커니즘:** 1. 정렬이나 조인을 위해 데이터를 읽음.
2. 메모리(PGA 내의 SQL Work Area)에서 처리하려고 보니 공간이 부족함.
3. 일단 읽은 데이터를 **Temp Tablespace(Disk)에 씀 (`direct path write`).
4. 나중에 정렬된 결과를 합치거나 조인하기 위해 Temp에서 다시 읽음 (`direct path read`**).
- 이때의 DPR은 단순 조회가 아니라 **"메모리가 부족해서 디스크를 메모리처럼 쓰느라"** 발생하는 심각한 성능 저하입니다.

---

### 2. 테스트 시나리오 추천

말씀하신 대로 극단적인 상황을 만들어 테스트해 볼 수 있습니다.

- **SGA 테스트:** `DB_CACHE_SIZE`를 작게 잡고, 테이블 크기가 버퍼 캐시보다 훨씬 큰 데이터를 Full Scan 하면 오라클이 "버퍼에 올려봤자 금방 밀려나겠네"라고 판단하여 DPR을 수행합니다.
- **PGA(Work Area) 테스트:** 이 방식이 훨씬 실무적입니다.
    - `PGA_AGGREGATE_TARGET`을 아주 작게 설정합니다.
    - 매우 큰 테이블 두 개를 `HASH JOIN` 하거나 대량의 데이터를 `ORDER BY` 합니다.
    - 그러면 `V$SESSION_WAIT`에서 `direct path read` (또는 `direct path read temp`)가 뜨는 것을 볼 수 있습니다.

---

### 3. SQL Work Area를 따로 늘릴 수 있나요?

네, 가능합니다. 하지만 오라클 버전에 따라 관리 방식이 다릅니다.

### A. 자동 관리 (권장 방식)

대부분의 현대 오라클 환경(10g 이후)에서는 시스템 전체의 PGA 총량을 설정하면 오라클이 알아서 개별 세션에 할당합니다.

```sql
ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 2G; -- 전체 PGA 크기 조절
```

### B. 수동/세션별 관리 (테스트나 특정 배치용)

특정 세션에서만 작업 영역을 강제로 크게 쓰고 싶을 때 사용합니다. (테스트할 때 유용합니다)

```sql
ALTER SESSION SET WORKAREA_SIZE_POLICY = MANUAL; -- 자동 관리 해제
ALTER SESSION SET SORT_AREA_SIZE = 104857600;   -- 정렬 공간을 100MB로 확장
ALTER SESSION SET HASH_AREA_SIZE = 209715200;   -- 해시 조인 공간 확장
```

---

### 💡 학습을 위한 실무 포인트

실무에서 `direct path read` 대기가 많이 보일 때, 엔지니어는 다음 질문을 던집니다.

1. **"Temp Tablespace를 쓰고 있는가?"** (`V$SORT_USAGE` 확인) -> 그렇다면 PGA가 부족한 것.
2. **"불필요한 Full Scan인가?"** -> 그렇다면 인덱스 누락.
3. **"통계 정보가 최신인가?"** -> 옵티마이저가 데이터 양을 오판해서 무리하게 Hash Join을 선택했을 가능성.

---

### 1단계: 테스트용 대량 데이터 생성

먼저 정렬할 대상이 될 테이블을 만듭니다. 약 100만 건 정도면 충분히 테스트가 가능합니다.

```sql
-- 테스트용 테이블 생성 (약 100만 건)
CREATE TABLE test_dpr_table AS
SELECT
    level AS id,
    LPAD('A', 100, 'A') AS dummy_data1, -- 블록 크기를 키우기 위한 더미 데이터
    LPAD('B', 100, 'B') AS dummy_data2,
    SYSDATE - (level/24/60) AS create_date
FROM dual
CONNECT BY level <= 1000000;

-- 통계 정보 생성 (옵티마이저가 데이터 양을 알게 함)
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'TEST_DPR_TABLE');
END;
/
```

---

### 2단계: 환경 설정 (PGA 극단적 축소)

현재 세션에서만 메모리를 아주 작게 제한합니다.

```sql
-- 수동 관리 모드로 변경
ALTER SESSION SET WORKAREA_SIZE_POLICY = MANUAL;

-- 정렬 공간을 64KB(최소 수준)로 제한
ALTER SESSION SET SORT_AREA_SIZE = 65536;
-- 해시 조인 공간도 제한
ALTER SESSION SET HASH_AREA_SIZE = 65536;
```

---

### 3단계: 테스트 실행 및 관찰 시나리오

### [터미널 A] : 실제 쿼리 실행

아래 쿼리를 실행합니다. 데이터가 많아 시간이 좀 걸릴 텐데, 이때 **[터미널 B]**로 가서 관찰하세요.

```sql
-- 100만 건을 날짜순으로 정렬 (64KB 메모리로는 절대 불가능 -> Temp 사용 강제)
SELECT * FROM test_dpr_table ORDER BY create_date DESC;
```

### [터미널 B] : 실시간 대기 이벤트 관찰 (다른 세션에서 실행)

쿼리가 돌아가는 동안 아래 쿼리들을 차례로 날려보세요.

```sql
-- 1. 현재 대기 중인 이벤트 확인 (direct path read/write가 뜨는지 확인)
SELECT sid, event, state, wait_time_micro
FROM v$session_wait
WHERE sid IN (SELECT sid FROM v$session WHERE username = '사용자명');

-- 2. SQL 작업 영역 상태 확인 (Multi-pass가 뜨면 메모리 부족으로 디스크 여러 번 썼다는 뜻)
SELECT sql_id, operation_type, policy, last_execution, work_area_size
FROM v$sql_workarea_active;

-- 3. Temp 세그먼트 사용량 확인
SELECT username, session_addr, tablespace, contents, segtype
FROM v$tempseg_usage;
```

---

### 4단계: 결과 분석

테스트가 끝나면 리포트에서 다음을 확인하세요.

- **`direct path write`**: 메모리에서 정렬 못 한 데이터를 Temp에 쓰는 중.
- **`direct path read`**: 정렬을 마치고 Temp에서 다시 결과를 읽어오는 중.

---

> 대기이벤트 범인 추적
> 

[대기이벤트 범인 추적](https://www.notion.so/3460f3217fe880debfead8bb0c884606?pvs=21) 

```jsx

SQL> SELECT
    event,
    session_id,
    COUNT(*) as wait_count
FROM v$active_session_history
WHERE sample_time > sysdate - 35/1440 -- 최근 5분
  AND event IS NOT NULL
GROUP BY event, session_id
ORDER BY wait_count DESC;  2    3    4    5    6    7    8    9

EVENT                          SESSION_ID WAIT_COUNT
------------------------------ ---------- ----------
direct path write temp                261        207
log file parallel write                 5         67
log file parallel write               258         37
db file sequential read               267         30
log file parallel write                 6         24
db file async I/O submit              384         20
LGWR any worker group                   5         16
log buffer space                      261         13
control file parallel write           131         12
db file scattered read                267         11
direct path sync                      261         10
LGWR all worker groups                  5         10
db file sequential read                19          9
db file sequential read                 8          9
external table read                     8          8
db file sequential read               261          8
control file parallel write           261          8
external table read                   267          8
direct path read                      267          7
Data file init write                  261          4
local write wait                       19          4
LGWR worker group ordering              6          4
log buffer space                      267          4
Disk file operations I/O              138          4
db file sequential read               144          3
LGWR worker group ordering            258          3
db file sequential read               149          3
latch free                            133          3
direct path write                     261          3
db file sequential read               142          3
local write wait                      261          3
control file heartbeat                 10          2
db file sequential read               151          2
latch free                            153          2
db file scattered read                397          2
db file scattered read                 19          2
enq: JG - queue lock                  266          2
db file sequential read               393          2
os thread creation                      1          2
Log archive I/O                        11          2
enq: TX - contention                   17          2
Disk file operations I/O               11          2
db file sequential read               401          2
AQ Background Master: slave st        270          2
art

latch free                             17          1

EVENT                          SESSION_ID WAIT_COUNT
------------------------------ ---------- ----------
latch free                            271          1
Disk file operations I/O              267          1
log file sequential read              138          1
db file sequential read               135          1
db file sequential read               273          1
ADR block file read                    10          1
latch free                             28          1
latch free                             31          1
latch free                            152          1
log buffer space                       19          1
db file sequential read               399          1
db file scattered read                401          1
enq: JG - queue lock                   19          1
library cache load lock               144          1
library cache load lock               395          1
cursor: pin S wait on X                19          1
cursor: pin S wait on X               393          1
oracle thread bootstrap                 8          1
latch free                            142          1
latch free                            393          1
direct path read                       19          1
db file sequential read               395          1
log file sequential read              261          1
library cache load lock               401          1
db file sequential read               145          1
library cache load lock               267          1
log file sync                         269          1
cursor: pin S wait on X               142          1
latch free                            391          1
latch free                            273          1
latch free                            277          1
db file single write                  261          1
Disk file operations I/O              261          1
db file scattered read                142          1
db file sequential read                28          1
ADR block file read                   395          1
db file sequential read               397          1
latch free                             22          1
buffer busy waits                     267          1
library cache load lock                28          1
db file sequential read                26          1
oracle thread bootstrap               266          1
log file sequential read              379          1
latch free                            386          1
latch free                            404          1
enq: CF - contention                  261          1
direct path write                      19          1

EVENT                          SESSION_ID WAIT_COUNT
------------------------------ ---------- ----------
oracle thread bootstrap               132          1
db file sequential read               275          1
db file sequential read                22          1
cursor: pin S wait on X               269          1
control file parallel write             8          1
latch free                             21          1
latch free                            269          1
local write wait                      267          1
reliable message                      267          1
db file sequential read               396          1
Log archive I/O                       138          1
library cache load lock               399          1

104 rows selected.

SQL>
SQL>
SQL>
SQL> direct path write temp                261        207
SP2-0734: unknown command beginning "direct pat..." - rest of line ignored.
SQL>
SQL> -- 세션 261번이 겪은 대기 이벤트와 당시의 SQL_ID 확인
SELECT
    sql_id,
    event,
    COUNT(*) as wait_count
FROM v$active_session_history
WHERE session_id = 261
  AND sample_time > sysdate - 30/1440 -- 최근 30분
GROUP BY sql_id, event
ORDER BY wait_count DESC;SQL>   2    3    4    5    6    7    8    9

SQL_ID        EVENT                          WAIT_COUNT
------------- ------------------------------ ----------
51ytts8jx72z7 direct path write temp                116
51ytts8jx72z7 control file parallel write             4
51ytts8jx72z7                                         4
51ytts8jx72z7 db file single write                    1
51ytts8jx72z7 local write wait                        1

SQL> SELECT sql_text
FROM dba_hist_sqltext
WHERE sql_id = '51ytts8jx72z7';  2    3

SQL_TEXT
--------------------------------------------------------------------------------
SELECT * FROM test_dpr_table ORDER BY create_date DESC

```

### 🎯 튜닝 엔지니어가 가져야 할 '의심의 단계'

1. **현상 파악**: `direct path write temp` 대기가 급증함 (특히 배치나 DML 부하가 없는 평소 상태에서).
2. **1차 의심 (SQL)**: "누가 이렇게 무식하게 정렬(Sort)이나 해시(Hash)를 크게 돌리고 있지?"
    - `V$SQL_WORKAREA_ACTIVE`나 ASH를 통해 범인 SQL을 검거합니다.
    - **체크리스트**: 실행 계획이 바뀌어서 인덱스 스캔이 Full Scan으로 변했는지, 혹은 통계 정보 오류로 해시 조인이 무리하게 선택됐는지 확인합니다.
3. **2차 의심 (Memory 세팅)**: "쿼리는 정상인데, 줄 수 있는 메모리(PGA)가 너무 짠 거 아냐?"
    - `PGA_AGGREGATE_TARGET` 수치가 적절한지, `workarea_size_policy`가 `AUTO`임에도 특정 세션에 할당되는 양이 너무 적은지 검토합니다.

---

### 💡 실무를 위한 마지막 팁: "Write가 더 위험한 이유"

오늘 테스트에서도 보셨듯이 `Read`보다 `Write`가 많이 보인다는 건, 시스템 입장에서는 **"나 지금 숨넘어가기 직전이라 일단 디스크에 버리고 있어!"**라는 비명 소리와 같습니다.

- **Read**는 필요한 데이터를 가져오는 '생산적 대기'일 수 있지만,
- *Write (Temp)**는 공간이 부족해서 발생하는 '낭비성 대기'이기 때문입니다.

---