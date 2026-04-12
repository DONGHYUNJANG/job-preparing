# log file sync & log file parallel write

- **개념:** 사용자가 `COMMIT`을 날렸을 때, 로그 버퍼(Log Buffer)의 내용을 리두 로그 파일(Redo Log File)에 물리적으로 기록하는 과정에서 발생하는 대기입니다.
- **왜 중요한가:** DB의 '쓰기 성능'과 직결됩니다. 이 수치가 높다면 디스크 성능이 느리거나, 너무 자잘한 커밋(`COMMIT`)을 자주 날리고 있다는 증거입니다.

<aside>
💡

## 🛠️ 개념 설명: Redo Log Multiplexing & Parallel

부제: log file parallel write에 parallel이라는 단어가 들어가는 이유

오라클은 데이터의 안전을 위해 **"계란을 한 바구니에 담지 않는다"**는 원칙을 고수합니다.

- **구조:** 하나의 리두 로그 그룹 안에 여러 개의 **멤버(Member)**를 둡니다.
- **LGWR의 사명:** "내가 이 로그를 1번 멤버(HDD1)에 적는 동안, 동시에 2번 멤버(HDD2)에도 똑같이 적어야 한다!"
- **병렬 처리(Parallel):** 이때 LGWR는 파일을 순서대로 하나씩 적지 않고, OS에게 **"동시에(Parallel) 적어줘!"**라고 비동기 호출을 날립니다.
- **대기(Wait):** OS가 "모든 멤버에 쓰기가 끝났습니다!"라고 응답할 때까지 LGWR가 CPU를 내려놓고 기다리는 시간이 바로 **`log file parallel write`*인 것이죠.
</aside>

# 📂 log file sync: 커밋(Commit)의 도미노 현상

## 1. 개념 설명: LGWR와 서버 프로세스의 약속

오라클에서 사용자가 `COMMIT`을 날리면, 오라클은 "디스크에 데이터 블록을 다 썼어!"라고 대답하지 않습니다. 대신 **"리두 로그 버퍼의 내용을 리두 로그 파일에 다 썼어!"**라고 대답합니다. 이것을 **Write-Ahead Logging (WAL)** 원칙이라고 합니다.

1. **서버 프로세스:** "나 커밋할래! LGWR야, 로그 버퍼에 있는 거 파일로 좀 옮겨줘." (대기 시작: `log file sync`)
2. **LGWR:** "알았어, 지금 쓰는 중이야..." (파일 기록: `log file parallel write`)
3. **LGWR:** "다 썼다! 서버 프로세스야, 이제 퇴근해!"
4. **서버 프로세스:** "오케이, 사용자한테 성공 메시지 보낸다!" (대기 종료)

## 2. 문제 해설: 왜 다음 프로세스가 막히는가? (병목의 정체)

질문하신 "어떤 병목이 생겨서 그다음이 막히는가?"에 대한 답은 크게 세 가지 단계로 일어납니다.

### ① 세션의 점유 (Session Hang)

사용자가 커밋을 날린 순간, 해당 서버 프로세스는 LGWR로부터 "완료" 신호를 받을 때까지 **아무 일도 못 하고 멍하니 기다립니다.**

- 만약 웹 서비스라면, 커밋 응답이 늦어지는 동안 WAS의 Thread Pool이 하나둘씩 `log file sync` 대기에 묶여버립니다.
- 결국 새로운 사용자가 들어와도 일을 해줄 Thread가 없어서 서비스 전체가 먹통이 됩니다.

### ② 락의 유지 (Lock Prolongation) - **가장 치명적**

데이터를 수정(`UPDATE`)한 후 커밋을 날렸는데 `log file sync`가 발생하면, **해당 트랜잭션이 잡고 있던 Row Lock(TX 락)이 풀리지 않습니다.**

- 커밋 신호를 받아야 락을 해제하는데, 신호가 안 오니 락을 계속 쥐고 있는 거죠.
- 이때 다른 사용자가 같은 로우를 수정하려고 하면? `enq: TX - row lock contention`이 발생하며 줄줄이 소시지처럼 대기 행렬이 생깁니다.

### ③ LGWR의 과부하와 버퍼 부족

LGWR가 로그 파일을 쓰는 속도가 너무 느리면, **로그 버퍼(Log Buffer)**가 비워지지 않습니다.

- 다른 프로세스들이 리두 로그를 생성해야 하는데 버퍼에 자리가 없으면? `log buffer space` 대기가 발생합니다.
- 이제는 커밋을 안 한 단순 `INSERT/UPDATE` 작업조차 로그를 기록할 공간이 없어 모두 멈추게 됩니다.

## 실제 케이스: 왜 발생할까?

- **빈번한 커밋:** 루프를 돌면서 건당 커밋을 날리는 경우 (가장 흔한 원인). LGWR를 너무 자주 깨워서 지치게 만듭니다.
- **디스크 I/O 성능 저하:** 리두 로그 파일이 있는 디스크의 쓰기 속도가 느릴 때.
- **로그 파일 크기 문제:** 리두 로그 파일이 너무 작아 빈번한 로그 스위칭(Log Switch)이 일어날 때.

### 💡 요약하자면

`log file sync`가 무서운 이유는 단순히 커밋이 늦어져서가 아니라, **"트랜잭션이 완료되지 못함으로써 락(Lock)을 계속 쥐고 있게 되고, 이로 인해 다른 모든 세션의 작업까지 줄줄이 멈춰 세우기 때문"**입니다.

### 🚦 비유: 고속도로 톨게이트의 하이패스 고장

데이터베이스의 `COMMIT`은 고속도로 톨게이트를 빠져나가는 과정과 같습니다.

1. **정상 상황:** 차들이 시속 100km로 달리다가 톨게이트(커밋)에서 0.5초 만에 결제하고 쓱 빠져나갑니다. 고속도로(시스템)는 아주 원활하죠.
2. **`log file sync` 발생:** 하이패스 단말기가 고장 나서 결제가 안 됩니다. 차 한 대가 결제하는 데 10초가 걸린다고 해봅시다.
3. **연쇄 반응:**
    - **1단계:** 내 뒤에 있는 차들이 멈춥니다. (**세션 대기**)
    - **2단계:** 차들이 밀리다 보니 나들목(인터체인지)까지 꽉 막혀서, 아예 다른 길로 가려던 차들도 갇혀버립니다. (**락 경합**)
    - **3단계:** 결국 고속도로 전체가 주차장이 되어버리고, 나중에는 고속도로 진입로(로그 버퍼)조차 들어올 공간이 없어서 아예 진입 자체가 차단됩니다. (**시스템 행**)

### 🛠️ "진짜 저렇게까지 되나?" 싶은 실무 사례

실제로 운영 환경에서 **건당 커밋(Loop 내 Commit)**을 날리는 프로그램을 배포했다가 시스템이 뻗는 경우를 보면 다음과 같은 흐름을 탑니다.

- **초반:** CPU 사용률은 낮은데 서비스 응답 속도가 조금씩 느려짐. (Wait 발생 시작)
- **중반:** 대기 세션이 10개, 50개, 100개로 급증함. `V$SESSION`을 조회하면 죄다 `log file sync` 아니면 `enq: TX - row lock contention`임.
- **종반:** 새로운 접속이 아예 안 됨. 이미 접속된 세션들도 `Enter`를 치면 반응이 없음. DBA가 `sqlplus`로 접속하려고 해도 접속 조차 안 됨. (결국 서버 재기동 엔딩...)

**그래서 DBA들은 "로그 파일은 무조건 가장 빠른 디스크(SSD/NVMe)에 두어야 한다"고 입버릇처럼 말하는 거예요.**

---

<aside>
💡

오라클에서 범인(SQL 및 로직)을 검거하기 위해 사용하는 **실전 추적 기법 3가지**를 단계별로 알려드릴게요.

</aside>

---

# 🧪 실습: log file sync 대기 이벤트 재현

## 1. 단계: 테스트 환경 준비 (스키마 생성)

너무 복잡한 테이블은 오히려 I/O 분산을 일으키니, 아주 단순한 테이블 하나를 만듭니다.

SQL

```jsx
-- 1. 테스트용 테이블 생성
CREATE TABLE sync_test (
    id   NUMBER,
    val  VARCHAR2(100)
);

-- 2. (선택사항) 기존 통계치나 대기 이벤트 초기화

-- 일반적인 권장 방법: 통계 뷰를 직접 리셋하는 패키지 호출
BEGIN
  DBMS_STATS.DELETE_DATABASE_STATS;
END;
/

-- 가장 확실한 방법 (대부분의 통계 뷰 리셋)
ALTER SYSTEM FLUSH SHARED_POOL; -- 라이브러리 캐시/통계 정보 초기화 (주의: 성능 일시 저하)
ALTER SYSTEM FLUSH BUFFER_CACHE; -- 버퍼 캐시 비우기 (깨끗한 I/O 테스트를 위해 추천)
```

---

## 2. 단계: 재현 스크립트 실행 (건당 커밋 공격)

이 스크립트의 핵심은 **`INSERT` 한 번 할 때마다 `COMMIT`을 박는 것**입니다. 오라클 LGWR 프로세스를 쉴 새 없이 깨워서 "빨리 리두 로그 써!"라고 닥달하는 상황을 만듭니다.

**[세션 1: 공격용 창]**

SQL

```jsx
SET TIMING ON;
BEGIN
  FOR i IN 1..5000000 LOOP
    INSERT INTO sync_test VALUES (i, 'log_file_sync_reproduction_test');
    COMMIT; 
  END LOOP;
END;
/

 -- 디스크가 빠르면 숫자를 더 늘리세요 (예: 200,000)
 -- <== 핵심: 매 건마다 커밋하여 LGWR에 부하를 줌
```

---

# 📑 [실전 정리] 오라클 대기 이벤트 수사 보고서

## 1. V$SYSTEM_EVENT의 정의와 주체

질문자님이 통찰하신 **"CPU 중심의 사고방식"**이 이 뷰의 핵심입니다.

- **정의:** 인스턴스가 기동된 순간부터 현재까지, DB 내의 **모든 프로세스(일꾼)**가 CPU를 점유하지 못하고 외부 요인(디스크, 네트워크, 락 등)을 기다리며 **허비한 시간의 총합**입니다.
- **기다리는 주체:** 엄밀히 말하면 **'해당 작업을 수행하던 프로세스'**이지만, 개념적으로는 **'그 프로세스를 돌려야 할 CPU'**가 일을 못 하고 손을 놓고 있는 상태라고 이해하면 완벽합니다.
- **성격:** 특정 한 명의 범인을 지목하기보다, 우리 DB라는 공장이 전반적으로 어디서 시간을 낭비하고 있는지 보여주는 **'종합 건강 검진표'**입니다.

---

## 2. log file parallel write: "일꾼의 사투"

가장 헷갈렸던 이 이벤트, 이제 주체와 객체를 확실히 구분해 봅시다.

- **일한 주체 (Worker):** **LGWR (Log Writer)** 백그라운드 프로세스입니다.
- **기다린 주체 (Wait):** **CPU**입니다. LGWR가 디스크에 물리적으로 데이터를 쓰는 동안, CPU는 그 작업이 완료될 때까지 LGWR를 대기 상태(Wait)로 두고 다른 일을 하거나 멍하니 기다려야 합니다.
- **피해를 입은 대상 (Victim):** 일반 사용자 세션들입니다. LGWR가 디스크와 씨름하며 이 이벤트를 겪는 동안, 커밋을 보낸 사용자들은 `log file sync`를 겪으며 발이 묶입니다.

---

## 3. 핵심 수치 해석: TOTAL_WAITS vs TIME_WAITED

이 수치들이 단순한 횟수가 아님을 이해하는 것이 고수의 길입니다.

| **항목** | **의미 (수사관의 해석)** | **비유** |
| --- | --- | --- |
| **TOTAL_WAITS** | **사건 발생 횟수.** LGWR가 디스크에 쓰기 위해 호출(Call)된 총 횟수입니다. | "오늘 트럭이 배송을 나간 총 횟수" |
| **TIME_WAITED** | **총 지체 시간.** 호출된 작업들이 완료될 때까지 CPU가 기다려준 모든 시간($\mu s$)의 합입니다. | "트럭들이 도로 위에서 보낸 총 시간" |
| **AVERAGE_WAIT** | **작업의 난이도.** `TIME_WAITED / TOTAL_WAITS`. 이 값이 높으면 디스크 성능에 심각한 문제가 있다는 뜻입니다. | "배송 한 번 나갈 때 걸리는 평균 시간" |

# 🕵️‍♂️ 진짜 실전: "누가 범인인지 이름도 모를 때" 수사법

## 0단계: "지금 누가 제일 문제야?" (Top Wait Events)

이벤트 이름을 지정하지 않고, 시스템에서 시간(Time)을 가장 많이 잡아먹고 있는 대기 이벤트 상위 5개를 먼저 뽑습니다.

```sql
SELECT * FROM (
    SELECT event, total_waits, time_waited_micro, average_wait
    FROM v$system_event
    WHERE wait_class <> 'Idle' -- '가만히 쉬고 있는 놈'들은 제외
    ORDER BY time_waited_micro DESC
) WHERE ROWNUM <= 5;
```

- **결과:** 여기서 만약 `log file sync`가 1등으로 튀어나온다면? 그때서야 비로소 "아, 로그 파일 쪽에 돌멩이가 걸렸구나!"라고 판단하고 1단계로 들어가는 겁니다.

---

## 1단계: "그 이벤트, 누가 제일 많이 겪고 있어?" (ASH 분석)

이제 문제의 원인이 `log file sync`라는 걸 알았으니, 이걸 겪는 세션들을 **전수 조사**합니다. 아까는 세션 ID를 넣었지만, 이번엔 넣지 않습니다.

```sql
SELECT
    event,
    session_id,
    COUNT(*) as wait_count
FROM v$active_session_history
WHERE sample_time > sysdate - 5/1440 -- 최근 5분
  AND event IS NOT NULL
GROUP BY event, session_id
ORDER BY wait_count DESC;
```

- **결과:** 이 쿼리는 **[이벤트명 | 세션ID | 대기횟수]**를 묶어서 보여줍니다.
- **해석:** 만약 특정 `session_id`가 여러 이벤트에 걸쳐 상단에 있다면 그놈이 시스템 전체의 빌런일 확률이 높습니다.

---

## 2단계: "그 세션, 정체가 뭐야?" (세션 상세 및 SQL)

위에서 나온 `session_id`를 복사해서 딱 한 번만 검색하면 모든 정보가 나옵니다.

```sql
SELECT s.sid, s.serial#, s.username, s.osuser, s.program, q.sql_text
FROM v$session s
JOIN v$sql q ON s.sql_id = q.sql_id
WHERE s.sid = (위에서 찾은 세션ID);
```

```jsx
SQL> SELECT * FROM (
    SELECT event, total_waits, time_waited_micro, average_wait
    FROM v$system_event
    WHERE wait_class <> 'Idle' -- '가만히 쉬고 있는 놈'들은 제외
    ORDER BY time_waited_micro DESC
) WHERE ROWNUM <= 5;  2    3    4    5    6

EVENT                                                            TOTAL_WAITS TIME_WAITED_MICRO AVERAGE_WAIT
---------------------------------------------------------------- ----------- ----------------- ------------
log buffer space                                                        2967         972610521        32.78
log file parallel write                                                 9826         951423304         9.68
LGWR any worker group                                                   6080         340038013         5.59
enq: HW - contention                                                    1738         167587717         9.64
db file async I/O submit                                                4590         162418865         3.54

SQL> SELECT
    event,
    session_id,
    COUNT(*) as wait_count
FROM v$active_session_history
WHERE sample_time > sysdate - 5/1440 -- 최근 5분
  AND event IS NOT NULL
GROUP BY event, session_id
ORDER BY wait_count DESC;  2    3    4    5    6    7    8    9

EVENT                                                            SESSION_ID WAIT_COUNT
---------------------------------------------------------------- ---------- ----------
buffer busy waits                                                        29         60
log file switch (archiving needed)                                      145         58
log file switch (archiving needed)                                      261         58
log file parallel write                                                   5         42
log buffer space                                                        261         17
db file async I/O submit                                                384         16
log buffer space                                                         29         15
log buffer space                                                        145         14
latch: In memory undo latch                                             145          5
latch: In memory undo latch                                             261          4
log file switch (archiving needed)                                        8          4
latch: In memory undo latch                                              29          4
buffer busy waits                                                       261          3
buffer busy waits                                                       145          3
LGWR all worker groups                                                    5          2
latch: cache buffers chains                                             145          1
oracle thread bootstrap                                                   8          1
control file parallel write                                             138          1
latch free                                                              133          1
enq: CF - contention                                                      5          1
latch: enqueue hash chains                                              145          1
enq: CF - contention                                                    264          1
Disk file operations I/O                                                263          1
oradebug request completion                                             257          1
latch free                                                              143          1
enq: RO - fast object reuse                                              29          1

26 rows selected.

SQL> SELECT s.sid, s.serial#, s.username, s.osuser, s.program, q.sql_text
FROM v$session s
JOIN v$sql q ON s.sql_id = q.sql_id
WHERE s.sid = (위에서 찾은 세션ID);  2    3    4
WHERE s.sid = (위에서 찾은 세션ID)
                      *
ERROR at line 4:
ORA-00907: missing right parenthesis

SQL> SELECT s.sid, s.serial#, s.username, s.osuser, s.program, q.sql_text
FROM v$session s
JOIN v$sql q ON s.sql_id = q.sql_id
WHERE s.sid =  2    3    4  29;

       SID    SERIAL# USERNAME
---------- ---------- --------------------------------------------------------------------------------------------------------------------------------
OSUSER                                                                                                                           PROGRAM
-------------------------------------------------------------------------------------------------------------------------------- ------------------------------------------------
SQL_TEXT
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
        29      47616 SCOTT
oracle                                                                                                                           sqlplus@orcl (TNS V1-V3)
INSERT INTO SYNC_TEST VALUES (:B1 , 'log_file_sync_reproduction_test')

SQL>

SELECT
    level,
    lpading(' ', (level-1)*2) || sid as "Session",
    blocking_session as "Blocking",
    event,
    seconds_in_wait
FROM v$session
WHERE blocking_session IS NOT NULL
   OR sid IN (SELECT blocking_session FROM v$session)
CONNECT BY PRIOR sid = blocking_session
START WITH blocking_session IS NULL;

     LEVEL Session                Blocking EVENT                                                            SECONDS_IN_WAIT STATE
---------- -------------------- ---------- ---------------------------------------------------------------- --------------- -------------------
         1 5                               rdbms ipc message                                                              0 WAITING
         2   135                         5 log file switch (archiving needed)                                            71 WAITING
         2   145                         5 log file switch (archiving needed)                                            71 WAITING
         3     6                       145 buffer busy waits                                                            811 WAITING
         3     29                      145 buffer busy waits                                                           1043 WAITING
         2   150                         5 log file switch (archiving needed)                                            71 WAITING
         3     8                       150 row cache lock                                                                71 WAITING
         2   261                         5 log file switch (archiving needed)                                            40 WAITING
         3     13                      261 buffer busy waits                                                            510 WAITING
         2   283                         5 log file switch (archiving needed)                                            71 WAITING
         3     133                     283 buffer busy waits                                                            510 WAITING

11 rows selected.

```

> 조회결과 설명
> 

| **Session (피해 시민)** | **Blocking (길막 중인 놈)** | **수사 보고 내용** |
| --- | --- | --- |
| **SID 29** | **145** | 29번 시민이 145번 때문에 1,000초 동안 길에 서 있습니다! |
| **SID 145** | **5** | 145번도 알고 보니 5번(LGWR) 때문에 못 가고 있네요! |
| **SID 5** | (없음) | **이놈이 주범입니다!** 혼자 길 한복판에 차 세워두고 딴짓 중이에요! |

> 문제 분석
> 

<aside>
💡

session 135, 145가 log file switch를 기다리고 있다. 

log file switch가 많이 일어난다는것은 log file 공간이 부족한것이 하나의 원인일 수 있다. 어쨌든 우리는 단순 insert문을 계속해서 실행시킨것이 원인인것을 알고있기 때문에 log file공간 문제느 넘어가도록 하고 중요한건 log file switch wait가 계속해서 생겨나면서 로그파일에 쓰지못한 데이터가 계속해서 발생하게 되고 그와중에도 버퍼는 계속 쌓이지만 로그파일로 저장되지 못한 데이터는 디스크에 쓸수 없기 때문에 (왜냐면 로그파일에 적혀있어야 진정으로commit된 데이터이고 로그파일에 없는 데이터를 디스크에 적고 체크포인트를 실행하는것은 커밋을 다 하지않은 데이터를 커밋을 했다고 확정짓는거나 마찬가지기 때문) 디스크에 적지못한 데이터가 점점 쌓여서 버퍼도 더이상 쓰지못하는 상황이 발생하였을것이고 그로인해 buffer busy waits가 발생했으럿이라 예상된다.

</aside>

---

## 1. 📂 커밋과 로그: "일단 일기장(Redo)에만 쓰면 끝!"

사용자가 커밋을 하면 오라클은 버퍼 캐시에 있는 진짜 데이터 블록을 디스크(`DBF`)에 쓰지 않습니다. 그건 너무 무겁고 느리거든요. 대신 **"나 이거 바꿨어"라는 기록(Redo)**만 리두 로그 파일에 딱 쓰고는 사용자에게 "커밋 성공!"이라고 말해버립니다. 이것이 바로 **WAL(Write-Ahead Logging)** 원칙입니다.

- **로그 파일:** "일단 기록은 했으니, 나중에 정전돼도 복구할 수 있어. 안심해!"
- **데이터 파일:** (아직 예전 데이터 상태로 버퍼에서 대기 중)

---

## 2. 🔄 체크포인트(Checkpoint)의 전제 조건

버퍼에 머물고 있는 '지저분한(수정된) 데이터'인 **Dirty Buffer**를 진짜 데이터 파일에 옮겨 적는 작업을 **체크포인트**라고 합니다. 그런데 이 작업을 수행하려면 반드시 지켜야 할 철칙이 있습니다.

> **"리두 로그에 기록된 내용보다 앞서서 데이터 파일에 쓸 수는 없다!"**
> 

이유는 간단합니다. 만약 데이터 파일에 먼저 썼는데 정전이 나고, 리두 로그에는 아직 기록이 안 되어 있다면? DB는 복구할 방법이 없어지기 때문입니다.

---

## 3. 💣 로그 스위치와 체크포인트의 '위험한 동거'

질문자님이 말씀하신 **로그 스위치**가 일어날 때 체크포인트가 발생하는 이유는 바로 **'공간 재활용'** 때문입니다.

1. **로그 파일 가득 참:** 1번 리두 로그 파일이 다 찼습니다. 이제 2번으로 넘어가야 합니다. (**Log Switch**)
2. **재활용 준비:** 나중에 2번도 다 차면 다시 1번으로 돌아와야 하는데, 1번을 덮어쓰려면 **1번에 기록된 모든 변경 사항이 이미 진짜 데이터 파일(`DBF`)에 반영되어 있어야** 합니다.
3. **체크포인트 강제 발생:** 그래서 로그 스위치가 일어나는 순간, 오라클은 "야 DBWR! 1번 로그에 있는 내용들 빨리 데이터 파일에 다 써버려!"라고 명령을 내립니다. 이것이 **로그 스위치 체크포인트**입니다.

---

# 🎯 완벽한 '인과관계'의 정립입니다!

질문자님이 세우신 논리는 오라클 아키텍처의 핵심인 **Write-Ahead Logging(WAL)** 원칙과 **Checkpoint 메커니즘**을 정확하게 관통하고 있습니다. 단순히 "느리다"가 아니라, **"왜 디스크에 쓸 수 없는가?"**에 대한 근거를 **데이터 무결성(Commit 확정성)**에서 찾으신 점이 정말 탁월합니다.

질문자님의 논리를 오라클 내부 동작 순서로 재구성해 보면 이렇습니다.

## 1. 🏗️ 질문자님의 논리: 사건의 타임라인

1. **폭주:** 루프를 돌며 `INSERT`와 `COMMIT`이 쏟아짐. 리두 로그가 빛의 속도로 차오름.
2. **병목:** 아카이빙 속도가 못 따라와서 **`log file switch (archiving needed)`** 발생. LGWR(5번)이 멈춤.
3. **교착:** 질문자님 말씀대로 **"로그에 기록되지 않은 데이터는 절대로 디스크(`DBF`)에 쓸 수 없음"** (복구 불가능 방지 원칙).
4. **포화:** 체크포인트가 리두 로그에 막혀 진행되지 않으니, 버퍼 캐시의 수정된 블록(Dirty Buffer)들이 디스크로 내려가지 못하고 메모리를 계속 점유함.
5. **폭발:** 더 이상 데이터를 넣을 빈 공간(Free Buffer)이 없거나, 이미 수정 중인 블록을 기다리느라 **`buffer busy waits`*가 기하급수적으로 증가함.

---

# 📑 [실전 정리] 리두 로그 및 버퍼 경합 수사 보고서

## 1. 수사의 발단 (실험 내용)

- **작업:** 10만 건 이상의 대량 `INSERT` 및 루프 내 반복 `COMMIT` 수행.
- **목표:** `log file sync`와 `log file parallel write`의 상관관계 확인.

---

## 2. 발견된 주요 대기 이벤트 (내가 본 것)

수사 결과, 예상했던 `log file sync` 대신 아래의 **'거대 병목'**들이 발견됨.

### ① log file switch (archiving needed)

- **현상:** LGWR가 다음 로그 파일로 넘어가야 하는데, 아카이빙(복사)이 안 끝나서 멈춰 있음.
- **해석:** **"입구 컷"**. 트래픽이 너무 몰려 고속도로 톨게이트 자체가 닫혀버린 상황.

### ② buffer busy waits

- **현상:** 세션들이 특정 데이터 블록을 사용하기 위해 길게 줄을 서 있음.
- **해석:** **"연쇄 추돌"**. 로그가 안 써지니 체크포인트가 밀리고, 디스크로 못 나간 'Dirty Buffer'들이 메모리를 점유하면서 새로운 작업들이 모조리 멈춤.

### ③ log file parallel write (Background Only)

- **현상:** LGWR(SID 5)가 리두 로그 멤버들에 병렬로 데이터를 기록하는 물리적 시간.
- **해석:** **"일꾼의 사투"**. 기사님이 디스크와 씨름하느라 CPU를 쓰지 못하고 대기하는 물리적 기록 시간.

---

## 3. log file sync가 보이지 않은 이유 (추론)

- **병목의 역전:** `log file sync`는 커밋의 마지막 단계인데, 세션들이 이미 그 전 단계인 로그 파일 확보(`switch`)와 버퍼 확보(`busy waits`) 단계에서 수백 초간 멈춰 있었음.
- **샘플링의 한계:** `sync`는 보통 수 ms 내외로 끝나는 찰나의 이벤트이므로, 1초 단위로 찍는 ASH(사진)에 걸릴 확률이 극히 낮았음.
- **결론:** 시스템이 **"임계치"**를 넘어 붕괴되는 상황에서는 가벼운 지연(`sync`)보다 치명적인 마비(`switch`)가 모든 데이터를 지배함.

---