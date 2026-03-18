# ONLINE_USERS 그룹 삭제

---

### STEP 1. Pending Area 생성

```sql
exec dbms_resource_manager.create_pending_area();
```

### STEP 2. 사용자 그룹 연결 해제

> ONLINE_USERS 그룹에 연결된 사용자들의 초기 Consumer Group을 다른 그룹으로 변경하거나 DEFAULT로 설정
> 

#### 3-1) ONLINE_USERS를 참조하는 Plan Directive 조회 (STEP2 수행 전 확인)

```sql
-- 전체 Plan들에서 ONLINE_USERS 참조 여부 확인
col plan for a20
col group_or_subplan for a20
col type for a20
SELECT plan,
       group_or_subplan,
       type
--       mgmt_p1, mgmt_p2, mgmt_p3, mgmt_p4, mgmt_p5, mgmt_p6,
--       active_sess_pool_p1,
--       parallel_degree_limit_p1,
--       switch_group,
--       switch_time,
--       switch_estimate
FROM   dba_rsrc_plan_directives
WHERE  group_or_subplan = 'ONLINE_USERS'
ORDER  BY plan, group_or_subplan;

-- 특정 Plan(DAYTIME)에서 ONLINE_USERS만 확인
SELECT plan, group_or_subplan, type
FROM   dba_rsrc_plan_directives
WHERE  plan = 'DAYTIME'
AND    group_or_subplan = 'ONLINE_USERS';
```

#### 3-2) Plan Directive 삭제

> **주의:** Consumer Group을 삭제하기 전에 해당 그룹을 참조하는 모든 Plan Directive를 먼저 삭제해야 한다.
> 

```sql
BEGIN
    dbms_resource_manager.delete_plan_directive(
        plan => 'DAYTIME',
        group_or_subplan => 'ONLINE_USERS'
    );
END;
/
```

#### 3-3) ONLINE_USERS 그룹에 연결된 사용자 조회

```sql
-- (가장 중요) 초기 Consumer Group이 ONLINE_USERS인 사용자
SELECT username, initial_rsrc_consumer_group
FROM   dba_users
WHERE  initial_rsrc_consumer_group = 'ONLINE_USERS'
ORDER  BY username;

-- (실시간) 현재 세션이 ONLINE_USERS로 분류되는 사용자(세션)
SELECT s.sid,
       s.serial#,
       s.username,
       s.machine,
       s.program,
       s.status,
       s.resource_consumer_group
FROM   v$session s
WHERE  s.username IS NOT NULL
AND    s.resource_consumer_group = 'ONLINE_USERS'
ORDER  BY s.username, s.sid;

-- (선택) 매핑 룰로 인해 ONLINE_USERS로 들어가는 케이스 확인
SELECT attribute, value, consumer_group, status
FROM   dba_rsrc_group_mappings
WHERE  consumer_group = 'ONLINE_USERS';
```

#### 3-4) 사용자별 Initial Consumer Group 변경

```sql
BEGIN
    dbms_resource_manager.set_initial_consumer_group(
        'SCOTT',
        'DEFAULT_CONSUMER_GROUP' 
    );
END;
/
```

### STEP 4. Consumer Group 삭제

```sql
BEGIN
    dbms_resource_manager.delete_consumer_group(
        consumer_group => 'ONLINE_USERS'
    );
END;
/
```

### STEP 5. 검증 및 적용

```sql
-- 검증
exec dbms_resource_manager.validate_pending_area();

-- 적용
exec dbms_resource_manager.submit_pending_area();
```

### ✅ 삭제 확인

```sql
-- Consumer Group 확인
SELECT consumer_group
FROM   dba_rsrc_consumer_groups
WHERE  consumer_group = 'ONLINE_USERS';

-- Plan Directive 확인
SELECT plan, group_or_subplan
FROM   dba_rsrc_plan_directives
WHERE  plan = 'DAYTIME';
```

> 💡 **참고사항**
> 
> - 그룹 삭제 시 해당 그룹을 사용하는 모든 Directive를 먼저 삭제해야 함
> - 그룹에 연결된 사용자가 있으면 먼저 다른 그룹으로 이동시켜야 함
> - SYS_GROUP과 OTHER_GROUPS는 시스템 기본 그룹이므로 삭제 불가