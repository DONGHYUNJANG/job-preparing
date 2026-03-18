# 리소스 매니저 day/night

## Day/Night 시나리오: 낮에는 일반 유저 우선, 밤에는 배치 유저 우선 (Linux cron 사용)

### 📌 시나리오 개요

> **낮 시간대 (DAYTIME)**: 일반 업무 유저(ONLINE_USERS)에게 CPU 우선권 부여
**밤 시간대 (NIGHTTIME)**: 배치 작업 유저(BATCH_USERS)에게 CPU 우선권 부여
**Linux cron**을 이용하여 시간대별 자동 플랜 전환
> 

---

### STEP 1. Pending Area 생성

```sql
exec dbms_resource_manager.create_pending_area();
```

---

### STEP 2. Consumer Group 생성

### 2-1. ONLINE_USERS 그룹 생성 (낮 시간대 우선)

```sql
BEGIN
    dbms_resource_manager.create_consumer_group(  
        'ONLINE_USERS',    
        'Users for Online daytime operations'
    );
END;
/
```

### 2-2. BATCH_USERS 그룹 생성 (밤 시간대 우선)

```sql
BEGIN
    dbms_resource_manager.create_consumer_group(  
        'BATCH_USERS',    
        'Users for Batch processing at night'
    );
END;
/
```

### ✅ 생성 확인

```sql
SELECT consumer_group
FROM   dba_rsrc_consumer_groups
WHERE  consumer_group IN ('ONLINE_USERS', 'BATCH_USERS');
```

---

### STEP 3. Resource Plan 생성

### 3-1. DAYTIME 플랜 생성 (낮 시간대)

```sql
BEGIN
    dbms_resource_manager.create_plan(
        'DAYTIME',
        'Plan for daytime - ONLINE_USERS priority'
    );
END;
/
```

### 3-2. NIGHTTIME 플랜 생성 (밤 시간대)

```sql
BEGIN
    dbms_resource_manager.create_plan(
        'NIGHTTIME',
        'Plan for nighttime - BATCH_USERS priority'
    );
END;
/
```

### ✅ 생성 확인

```sql
SELECT plan
FROM   dba_rsrc_plans
WHERE  plan IN ('DAYTIME', 'NIGHTTIME');
```

---

### STEP 4. DAYTIME Plan Directive 설정 (낮 시간대)

> **낮 시간대 전략**: ONLINE_USERS가 CPU 최우선, BATCH_USERS는 최소 자원만 할당
> 

### 4-1. SYS_GROUP — CPU 1순위 100%

```sql
BEGIN
    dbms_resource_manager.create_plan_directive(
        'DAYTIME',
        'SYS_GROUP',
        'System priority',
        cpu_p1 => 100
    );
END;
/
```

### 4-2. ONLINE_USERS — CPU 2순위 80%, block 타임 30초, sql실행시간 제한 10초

```sql
BEGIN
    dbms_resource_manager.create_plan_directive(
        'DAYTIME',
        'ONLINE_USERS',
        'Online users high priority during day',
        cpu_p2 => 80,
        max_idle_blocker_time => 30,
        max_est_exec_time => 10
    );
END;
/
```

### 4-3. BATCH_USERS — CPU 2순위 10%

```sql
BEGIN
    dbms_resource_manager.create_plan_directive(
        'DAYTIME',
        'BATCH_USERS',
        'Batch users low priority during day',
        cpu_p2 => 10,
        parallel_degree_limit_p1 => 2
    );
END;
/
```

### 4-4. OTHER_GROUPS — CPU 2순위 10%

```sql
BEGIN
    dbms_resource_manager.create_plan_directive(
        'DAYTIME',
        'OTHER_GROUPS',
        'Other users minimal resources',
        cpu_p2 => 10,
        max_idle_blocker_time => 30,
        max_est_exec_time => 10
    );
END;
/
```

---

### STEP 5. NIGHTTIME Plan Directive 설정 (밤 시간대)

> **밤 시간대 전략**: BATCH_USERS가 CPU 최우선, ONLINE_USERS는 최소 자원만 할당
> 

### 5-1. SYS_GROUP — CPU 1순위 100%

```sql
BEGIN
    dbms_resource_manager.create_plan_directive(
        'NIGHTTIME',
        'SYS_GROUP',
        'System priority',
        cpu_p1 => 100
    );
END;
/
```

### 5-2. BATCH_USERS — CPU 2순위 80%

```sql
BEGIN
    dbms_resource_manager.create_plan_directive(
        'NIGHTTIME',
        'BATCH_USERS',
        'Batch users high priority at night',
        cpu_p2 => 80,
        parallel_degree_limit_p1 => 8
    );
END;
/
```

### 5-3. ONLINE_USERS — CPU 2순위 10%

```sql
BEGIN
    dbms_resource_manager.create_plan_directive(
        'NIGHTTIME',
        'ONLINE_USERS',
        'Online users low priority at night',
        cpu_p2 => 10
    );
END;
/
```

### 5-4. OTHER_GROUPS — CPU 2순위 10%

```sql
BEGIN
    dbms_resource_manager.create_plan_directive(
        'NIGHTTIME',
        'OTHER_GROUPS',
        'Other users minimal resources',
        cpu_p2 => 10
    );
END;
/
```

---

### STEP 6. 검증 및 적용

### 6-1. 검증

```sql
exec dbms_resource_manager.validate_pending_area();
```

### 6-2. 적용

```sql
exec dbms_resource_manager.submit_pending_area();
```

---

### STEP 7. 설정 결과 조회

### 7-1. DAYTIME 플랜 확인

```sql
SELECT plan,
       group_or_subplan,
       cpu_p1,
       cpu_p2,
       parallel_degree_limit_p1 AS dop,
       MAX_EST_EXEC_TIME,
       max_idle_blocker_time AS block_t
FROM   dba_rsrc_plan_directives
WHERE  plan = 'DAYTIME'
ORDER BY cpu_p1 DESC NULLS LAST, cpu_p2 DESC;
```

> 📋 **예상 결과 (DAYTIME)**
> 

| PLAN | GROUP_OR_SUBPLAN | CPU_P1 | CPU_P2 | DOP | MAX_EST_EXEC_TIME | BLOCK_T |
| --- | --- | --- | --- | --- | --- | --- |
| DAYTIME | SYS_GROUP | 100 | 0 | - | - | - |
| DAYTIME | ONLINE_USERS | 0 | 80 | - | 10 | 30 |
| DAYTIME | BATCH_USERS | 0 | 10 | 2 | - | - |
| DAYTIME | OTHER_GROUPS | 0 | 10 | - | 10 | 30 |

### 7-2. NIGHTTIME 플랜 확인

```sql
SELECT plan,
       group_or_subplan,
       cpu_p1,
       cpu_p2,
       MAX_EST_EXEC_TIME,
       parallel_degree_limit_p1 AS dop
FROM   dba_rsrc_plan_directives
WHERE  plan = 'NIGHTTIME'
ORDER BY cpu_p1 DESC NULLS LAST, cpu_p2 DESC;
```

> 📋 **예상 결과 (NIGHTTIME)**
> 

| PLAN | GROUP_OR_SUBPLAN | CPU_P1 | CPU_P2 | MAX_EST_EXEC_TIME | DOP |
| --- | --- | --- | --- | --- | --- |
| NIGHTTIME | SYS_GROUP | 100 | 0 | - | - |
| NIGHTTIME | BATCH_USERS | 0 | 80 | - | 8 |
| NIGHTTIME | ONLINE_USERS | 0 | 10 | - | - |
| NIGHTTIME | OTHER_GROUPS | 0 | 10 | - | - |

---

### STEP 8. 유저를 Consumer Group에 연결

### 8-1. ONLINE_USERS 그룹 권한 부여 (예: SCOTT)

```sql
BEGIN
    dbms_resource_manager_privs.grant_switch_consumer_group(
        'SCOTT',
        'ONLINE_USERS',
        true
    );
    
    dbms_resource_manager.set_initial_consumer_group(
        'SCOTT',
        'ONLINE_USERS'
    );
END;
/
```

### 8-2. BATCH_USERS 그룹 권한 부여 (예: BATCH_USER)

```sql
BEGIN
    dbms_resource_manager_privs.grant_switch_consumer_group(
        'BATCH_USER',
        'BATCH_USERS',
        true
    );
    
    dbms_resource_manager.set_initial_consumer_group(
        'BATCH_USER',
        'BATCH_USERS'
    );
END;
/
```

### 8-3. 유저별 그룹 확인

```sql
SELECT username,
       initial_rsrc_consumer_group
FROM   dba_users
WHERE  username IN ('SCOTT', 'BATCH_USER');
```

---

### STEP 9. Linux cron을 이용한 시간대별 자동 전환

### 9-1. 쉘 스크립트 작성

### 📁 /home/oracle/scripts/switch_to_daytime.sh

```bash
#!/bin/bash
# DAYTIME 플랜으로 전환 (오전 8시)

LOG_FILE="/home/oracle/logs/resource_plan.log"

# 로그에 실행 시각 기록
echo "==========================================" >> $LOG_FILE
echo "[DAYTIME SWITCH] Date : $(date)" >> $LOG_FILE

# sqlplus 실행 결과를 로그 파일에 추가 (>> $LOG_FILE)
sqlplus -s / as sysdba <<EOF >> $LOG_FILE 2>&1
ALTER SYSTEM SET resource_manager_plan = 'DAYTIME';
SELECT name, value FROM v\$parameter WHERE name = 'resource_manager_plan';
EXIT;
EOF

# 3. 종료 메시지 기록
echo "Result: Daytime plan applied successfully." >> $LOG_FILE
echo "------------------------------------------" >> $LOG_FILE
```

### 📁 /home/oracle/scripts/switch_to_nighttime.sh

```bash
#!/bin/bash
# NIGHTTIME 플랜으로 전환 (오후 6시)

# 로그 파일 경로 설정
LOG_FILE="/home/oracle/logs/resource_plan.log"

# 1. 로그에 실행 시작 시각 기록
echo "==========================================" >> $LOG_FILE
echo "[NIGHTTIME SWITCH] Date : $(date)" >> $LOG_FILE

# 2. sqlplus 실행 및 로그 파일로 결과 리다이렉션 (>> $LOG_FILE 2>&1)
sqlplus -s / as sysdba <<EOF >> $LOG_FILE 2>&1
ALTER SYSTEM SET resource_manager_plan = 'NIGHTTIME';
-- 현재 적용된 플랜 확인 쿼리 추가
SELECT name, value FROM v\$parameter WHERE name = 'resource_manager_plan';
EXIT;
EOF

# 3. 종료 메시지 기록
echo "Result: Nighttime plan applied successfully." >> $LOG_FILE
echo "------------------------------------------" >> $LOG_FILE
```

### 9-2. 스크립트 실행 권한 부여

```bash
chmod +x /home/oracle/scripts/switch_to_daytime.sh
chmod +x /home/oracle/scripts/switch_to_nighttime.sh
```

### 9-3. crontab 설정

```bash
# oracle 유저로 crontab 편집
crontab -e
```

### crontab 내용 추가

```bash
# 매일 오전 8시에 DAYTIME 플랜으로 전환
0 8 * * * /home/oracle/scripts/switch_to_daytime.sh >> /home/oracle/logs/resource_plan.log 2>&1

# 매일 오후 6시에 NIGHTTIME 플랜으로 전환
0 18 * * * /home/oracle/scripts/switch_to_nighttime.sh >> /home/oracle/logs/resource_plan.log 2>&1
```

### 9-4. crontab 설정 확인

```bash
crontab -l
```

### 9-5. 로그 디렉토리 생성

```bash
mkdir -p /home/oracle/logs
touch /home/oracle/logs/resource_plan.log
```

---

### STEP 10. 수동 전환 방법 (테스트용)

### 10-1. DAYTIME 플랜으로 전환

```sql
ALTER SYSTEM SET resource_manager_plan = DAYTIME;
```

### 10-2. NIGHTTIME 플랜으로 전환

```sql
ALTER SYSTEM SET resource_manager_plan = NIGHTTIME;
```

### 10-3. 현재 적용된 플랜 확인

```sql
SELECT name, value
FROM   v$parameter
WHERE  name = 'resource_manager_plan';
```

### 10-4. Linux에서 수동 실행 테스트

```bash
# DAYTIME으로 전환 테스트
/home/oracle/scripts/switch_to_daytime.sh

# NIGHTTIME으로 전환 테스트
/home/oracle/scripts/switch_to_nighttime.sh

# 로그 확인
tail -f /home/oracle/logs/resource_plan.log
```

---

## 🔍 동작 원리 요약

| 시간 | cron 실행 | Resource Plan | 우선 그룹 | CPU 할당 |
| --- | --- | --- | --- | --- |
| **08:00** | switch_to_daytime.sh | DAYTIME | ONLINE_USERS | 80% |
| **18:00** | switch_to_nighttime.sh | NIGHTTIME | BATCH_USERS | 80% |

> 💡 **핵심 포인트**
> 
> - **낮 시간대 (08:00-18:00)**: 일반 업무 유저(ONLINE_USERS)가 CPU 80%를 사용하고, 배치 유저(BATCH_USERS)는 10%만 사용
> - **밤 시간대 (18:00-08:00)**: 배치 유저(BATCH_USERS)가 CPU 80%를 사용하고, 병렬도도 8로 증가하여 대량 작업 수행
> - **Linux cron 자동 전환**: 매일 08:00, 18:00에 자동으로 Resource Plan 전환
> - **로그 기록**: /home/oracle/logs/resource_plan.log에 전환 이력 저장
> - **SYS_GROUP**은 항상 최우선(CPU_P1=100)으로 시스템 작업 보장

---

### 🛠️ 트러블슈팅

### cron이 실행되지 않을 때

```bash
# cron 서비스 상태 확인
systemctl status crond

# cron 서비스 시작
systemctl start crond

# cron 서비스 자동 시작 설정
systemctl enable crond
```

### 스크립트 실행 오류 확인

```bash
# 로그 파일 확인
cat /home/oracle/logs/resource_plan.log
```

### 수동 테스트

```bash
# oracle 유저로 전환
su - oracle

# 스크립트 직접 실행
sh -x /home/oracle/scripts/switch_to_daytime.sh
```

> UNDO제한을 DAYTIME에 추가하고 싶다면
> 

<aside>
💡

## 🟢 UNDO_POOL이란?

- **정의**: 특정 컨슈머 그룹에 속한 세션들이 생성할 수 있는 **최대 Undo 데이터 양(KB)**입니다.
- **작동 방식**: 그룹 내 세션들이 사용 중인 Undo 합계가 이 수치에 도달하면, 해당 그룹의 사용자가 추가적인 DML(Insert, Update, Delete)을 시도할 때 **ORA-02044** 에러가 발생하며 작업이 차단됩니다.
- **특징**: `UNLIMITED`(기본값)로 두면 전체 Undo 테이블스페이스가 꽉 찰 때까지 쓸 수 있지만, 특정 그룹이 과도하게 Undo를 점유하여 시스템 전체에 영향을 주는 것을 방지할 때 사용합니다.

## 🔵 얼마나 지정하면 좋을까? (산정 기준)

정답이 정해져 있지는 않지만, 보통 다음과 같은 단계를 거쳐 결정합니다.

1. **전체 Undo 사이즈 확인**: 현재 시스템의 `UNDO_TABLESPACE` 크기를 먼저 파악합니다.
2. **그룹별 비중 할당**:
    - **중요 업무 그룹**: 전체의 50~70% 등 넉넉하게 할당.
    - **배치/임시 그룹**: 전체의 20~30% 등으로 제한하여 다른 그룹의 공간을 침범하지 못하게 방지.
3. **최대 트랜잭션 예측**: 해당 그룹에서 발생할 수 있는 가장 큰 단일 트랜잭션(예: 대용량 Update)의 크기보다 약간 크게 잡아야 업무가 중단되지 않습니다.
</aside>

#### Step 0. Resource Plan 지정

```jsx
alter system set resource_manager_plan='daytime';
```

#### Step 1. Pending Area 생성

```jsx
exec dbms_resource_manager.create_pending_area();
```

- Resource Manager 설정을 변경하기 전에 반드시 **Pending Area(임시 작업 공간)** 를 먼저 열어야 한다.
- 모든 변경 사항은 Submit 전까지 실제로 적용되지 않는다.

#### Step 2. Plan Directive 수정 (UNDO 제한 설정)

```jsx
begin
    dbms_resource_manager.update_plan_directive(
      plan             => 'DAYTIME',
      group_or_subplan  => 'ONLINE_USERS',
      new_undo_pool     => 1000000);   -- KB단위
end;
/
```

- `DAYTIME` 플랜 안의 `ONLINE_USERS` 그룹에 대해 UNDO 사용량 상한을 **1G**로 설정한다.
- `update_plan_directive`는 이미 존재하는 Directive를 **수정**할 때 사용한다.

#### Step 3. Pending Area 제출 (실제 적용)

```jsx
exec dbms_resource_manager.submit_pending_area();
```

- Pending Area에 쌓인 변경 내용을 **DB에 실제로 반영**한다.
- 이 단계 전까지는 변경 효과가 없다.

### 전체 흐름 요약

<aside>
🧩

```
create_pending_area()          ← 작업 공간 열기
      ↓
update_plan_directive(...)     ← UNDO 제한 설정 (10KB)
      ↓
submit_pending_area()          ← 실제 DB에 반영
```

</aside>

### 설정 확인 방법

```jsx
SELECT plan, group_or_subplan, undo_pool
FROM   dba_rsrc_plan_directives
WHERE  plan = 'DAYTIME';
```

<aside>
💡

필요에 따라 OTHER_GROUPS나 BATCH_USERS에도 추가

</aside>

### DAYTIME 플랜 확인

```sql
SELECT plan,
       group_or_subplan,
       cpu_p1,
       cpu_p2,
       parallel_degree_limit_p1 AS dop,
       MAX_EST_EXEC_TIME,
       max_idle_blocker_time AS block_t,
       UNDO_POOL
FROM   dba_rsrc_plan_directives
WHERE  plan = 'DAYTIME'
ORDER BY cpu_p1 DESC NULLS LAST, cpu_p2 DESC;
```