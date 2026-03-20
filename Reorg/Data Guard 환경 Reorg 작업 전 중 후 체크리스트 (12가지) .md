# Data Guard 환경 Reorg 작업 전/중/후 체크리스트 (12가지)

---

---

# 1️⃣ FORCE LOGGING 상태 확인

먼저 반드시 확인합니다.

```sql
SELECT force_logging
FROM v$database;
```

결과

| 값 | 의미 |
| --- | --- |
| YES | NOLOGGING 무효 |
| NO | NOLOGGING 가능 (위험) |

대부분 운영 DB는

```
FORCE LOGGING = YES
```

입니다.

---

# 2️⃣ Standby 상태 확인

Standby가 정상인지 먼저 확인합니다.

```sql
SELECT database_role, open_mode
FROM v$database;
```

Standby에서

```
PHYSICAL STANDBY
READ ONLY WITH APPLY
```

이면 정상입니다.

---

# 3️⃣ Apply Lag 확인 (매우 중요)

Reorg 전에 lag가 이미 크면 작업하면 안됩니다.

```sql
SELECT name,value
FROM v$dataguard_stats
WHERE name='apply lag';
```

기준

| lag | 판단 |
| --- | --- |
| 0~1분 | 정상 |
| 5분 이상 | 위험 |
| 30분 이상 | 작업 금지 |

---

# 4️⃣ Transport Lag 확인

Redo가 standby로 잘 전달되는지 확인

```sql
SELECT name,value
FROM v$dataguard_stats
WHERE name='transport lag';
```

transport lag가 있으면

```
network
archivelog
standby issue
```

가능성 있음.

---

# 5️⃣ FRA 공간 확인 (매우 중요)

Reorg는 redo 폭증합니다.

```sql
SELECT
space_limit/1024/1024/1024 GB_LIMIT,
space_used/1024/1024/1024 GB_USED
FROM v$recovery_file_dest;
```

권장

```
FRA 사용률 < 70%
```

80% 넘으면 위험.

---

# 6️⃣ Archive Log 생성량 확인

Reorg 시 archive log 급증합니다.

```sql
SELECT
trunc(completion_time),
count(*)
FROM v$archived_log
GROUP BY trunc(completion_time)
ORDER BY 1;
```

평소 대비 얼마나 늘어날지 예상합니다.

---

# 7️⃣ Standby Redo Log 상태 확인

SRL 문제 있으면 apply 멈출 수 있습니다.

```sql
SELECT group#, status
FROM v$standby_log;
```

정상 상태

```
ACTIVE
UNASSIGNED
```

---

# 8️⃣ Reorg 대상 크기 확인

redo 발생량 예측용

```sql
SELECT segment_name,
bytes/1024/1024 MB
FROM dba_segments
WHERE owner='SH'
AND segment_type='TABLE';
```

대략

```
redo ≈ table size
```

---

# 9️⃣ Standby Apply Process 확인

Standby에서 apply가 실제 돌아가는지 확인

```sql
SELECT process,status
FROM v$managed_standby;
```

정상

```
MRP0 APPLYING_LOG
```

---

# 🔟 Reorg 중 Standby Lag 모니터링

작업 중 계속 확인합니다.

```sql
SELECT name,value
FROM v$dataguard_stats
WHERE name='apply lag';
```

만약

```
lag > 30 min
```

이면

→ 작업 속도 줄이거나 중단 고려

---

# 1️⃣1️⃣ Reorg 후 Block Corruption 확인

Standby에서 체크합니다.

```sql
SELECT *
FROM v$database_block_corruption;
```

결과

```
no rows selected
```

이어야 정상.

---

# 1️⃣2️⃣ Standby Catch-up 확인

Reorg 끝난 후 standby가 따라잡는지 확인합니다.

```sql
SELECT name,value
FROM v$dataguard_stats
WHERE name='apply lag';
```

목표

```
lag → 0
```

---

# 📊 DBA들이 실제로 보는 핵심 5개

12개 중에서도 특히 중요한 것

1️⃣ FORCE LOGGING

2️⃣ Apply Lag

3️⃣ FRA usage

4️⃣ MRP0 status

5️⃣ Block corruption

이 5개만 봐도 **90% 사고 예방됩니다.**

---

# 💡 실제 현장에서 제일 많이 터지는 사고 TOP3

### 1️⃣ FRA Full

```
redo 폭증
→ archive 안됨
→ database hang
```

---

### 2️⃣ Standby Lag 폭증

```
reorg
→ redo flood
→ standby apply lag 3시간
```

---

### 3️⃣ NOLOGGING 실수

```
nologging operation
→ standby block corruption
```

---

# 🔧 DBA들이 보통 추가하는 스크립트

Reorg 중 계속 모니터링

```sql
SELECT
SYSDATE,
(SELECT value FROM v$dataguard_stats WHERE name='apply lag') APPLY_LAG,
(SELECT value FROM v$dataguard_stats WHERE name='transport lag') TRANSPORT_LAG
FROM dual;
```

5분마다 확인합니다.

---

✅ **정리**

Data Guard 환경 Reorg 핵심은

```
redo 폭증 관리
+
standby lag 관리
+
FRA 관리
```

입니다.

---

원하시면 제가 **“Oracle Reorg 할 때 DBA들이 실제로 가장 많이 쓰는 15개 SQL 모니터링 스크립트 세트”**도 만들어 드릴게요.

이거 하나 있으면 **주말 Reorg 할 때 계속 띄워놓고 보는 대시보드 수준**입니다.