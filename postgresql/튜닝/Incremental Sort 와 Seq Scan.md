# 튜닝 용어

> Seq Scan on emp
> 

Full Scan을 의미함

```jsx
 Seq Scan on emp  (cost=0.00..1.18 rows=5 width=44) (actual time=0.016..0.022 rows=14 loops=1)
   Filter: ((ename)::text > '   '::text)
   Buffers: shared hit=1
 Planning:
   Buffers: shared hit=18 read=1
 Planning Time: 0.377 ms
 Execution Time: 0.049 ms
(7 rows)

```

> Incremental Sort
> 

PostgreSQL의 **Incremental Sort**(증분 정렬)는 데이터베이스 성능 최적화의 숨은 공신 중 하나입니다. 주로 버전 13부터 도입되어 널리 쓰이기 시작한 기능으로, 모든 데이터를 처음부터 끝까지 다시 정렬하는 낭비를 줄여줍니다.
핵심은 **"이미 정렬된 데이터의 성질을 이용해 나머지 부분만 정렬한다"**는 것입니다.

## 1. Incremental Sort의 기본 개념

일반적인 정렬(Full Sort)은 전체 데이터셋을 메모리나 디스크에 올린 뒤 정렬을 수행합니다. 반면, Incremental Sort는 데이터가 이미 특정 컬럼을 기준으로 **부분적으로 정렬되어 있을 때**, 추가로 필요한 정렬 작업만 수행합니다.

### 동작 예시

다음과 같은 쿼리가 있다고 가정해 봅시다:
SELECT * FROM sales ORDER BY date, price;

- **인덱스 상황:** date 컬럼에만 인덱스가 걸려 있음.
- **기존 방식 (Full Sort):** date 인덱스를 타더라도, price까지 정렬하기 위해 전체 데이터를 다시 정렬함.
- **증분 정렬 방식:** 이미 date별로 모여 있는 데이터 그룹 안에서만 price를 정렬함.

## 2. 작동 원리

Incremental Sort는 데이터를 **'Pre-sorted'**(이미 정렬된) 그룹으로 나눕니다.

1. **그룹화:** 선행 정렬 기준(예: date)에 따라 데이터를 읽습니다.
2. **부분 정렬:** 같은 date 값을 가진 행들(Batch)만 모아서 후행 기준(price)으로 정렬합니다.
3. **결과 반환:** 한 그룹의 정렬이 끝나면 즉시 결과를 반환할 수 있습니다.

## 3. 주요 장점

### 1) 빠른 응답 속도 (Low Latency)

전체 데이터를 다 읽고 정렬할 때까지 기다릴 필요가 없습니다. 첫 번째 그룹의 정렬이 끝나면 즉시 결과를 사용자에게 던져줄 수 있어, LIMIT 절과 함께 사용할 때 특히 강력합니다.

### 2) 메모리 절약

전체 데이터셋을 한꺼번에 정렬하지 않고 작은 그룹(Batch) 단위로 정렬하기 때문에, 정렬에 필요한 **Work_mem** 사용량이 줄어듭니다.

## 4. 실행 계획 확인법

EXPLAIN 명령어를 통해 Incremental Sort가 작동하는지 확인할 수 있습니다.

```sql
EXPLAIN SELECT * FROM orders ORDER BY customer_id, order_date;
```

**실행 결과 예시:**

```
Incremental Sort  (cost=0.42..154.20 rows=1000 width=40)
  Sort Key: customer_id, order_date
  Presorted Key: customer_id
  ->  Index Scan using idx_customer_id on orders  (cost=0.29..120.50 rows=1000 width=40)
```

- Presorted Key: 이미 정렬된 상태로 읽어온 기준 컬럼을 나타냅니다.

## 5. 주의사항 및 팁

- **통계 정보:** PostgreSQL 옵티마이저가 Incremental Sort를 선택하려면 데이터 분포에 대한 통계가 정확해야 합니다.
- **인덱스 설계:** 복합 인덱스를 만들기 어려운 상황(예: 인덱스 크기 문제)에서 선행 컬럼에만 인덱스를 걸어두어도 성능 이득을 볼 수 있게 해줍니다.
- **설정값:** enable_incrementalsort 파라미터를 통해 이 기능을 끄거나 켤 수 있습니다 (기본값은 on).


오라클의 **Incremental Sort**는 12c R2부터 도입된 최적화 기술로, 모든 데이터를 처음부터 끝까지 정렬하는 대신 **이미 정렬된 부분 집합(Prefix)을 활용하여 나머지 데이터만 정렬**하는 효율적인 방식입니다.

# 오라클에서의 Incremental Sort

---

### 1. 개념 설명

기본적으로 정렬 작업은 메모리(PGA)와 CPU를 많이 소모하는 무거운 작업입니다. 만약 `ORDER BY A, B`라는 쿼리가 있을 때, 데이터가 이미 `A` 컬럼으로 정렬되어 있다면 어떨까요?

* **기존 방식:** `A`가 정렬되어 있더라도 무시하고 `(A, B)` 전체 조합을 다시 정렬합니다.
* **Incremental Sort:** 이미 정렬된 `A`를 기준으로 데이터를 그룹화(Window)하고, 각 그룹 내에서만 `B`를 정렬합니다.

즉, 전체 데이터를 한꺼번에 정렬하는 것이 아니라, 선행 컬럼의 정렬 상태를 신뢰하여 **정렬 단위를 잘게 쪼개어 수행**하는 것입니다.


---

### 2. 작동 원리 및 특징

1.  **Prefix 활용:** 인덱스나 이전 단계의 연산으로 인해 정렬된 컬럼을 'Prefix'로 인식합니다.
2.  **데이터 스트리밍:** 전체 데이터를 다 읽은 후 정렬을 시작하는 것이 아니라, 정렬된 Prefix가 같은 동안 데이터를 읽어 들이며 그 안에서만 후속 컬럼 정렬을 수행합니다.
3.  **리소스 절약:** * **PGA 메모리:** 한 번에 정렬해야 할 데이터 양이 줄어들어 메모리 사용량이 감소합니다.
    * **응답 속도:** 첫 번째 로우를 반환하는 속도(First-row Response)가 획기적으로 빨라집니다. 특히 `STOP KEY`와 결합될 때 매우 강력합니다.

---

### 3. 문제 해설 (실행 계획 분석)

OCP 시험이나 실무 면접에서 실행 계획을 볼 때 아래와 같은 연산자를 확인해야 합니다.

#### **실행 계획 예시**
```sql
---------------------------------------------------------------------------------------
| Id  | Operation                        | Name       | Rows  | Bytes | Cost (%CPU)|
---------------------------------------------------------------------------------------
|   0 | SELECT STATEMENT                 |            |    10 |   400 |     3  (0) |
|   1 |  SORT ORDER BY INCREMENTAL       |            |    10 |   400 |     3  (0) |
|   2 |   TABLE ACCESS BY INDEX ROWID    | EMP        |    10 |   400 |     2  (0) |
|* 3 |    INDEX RANGE SCAN              | IDX_DEPTNO |    10 |       |     1  (0) |
---------------------------------------------------------------------------------------
```

* **설명:** 1.  `IDX_DEPTNO` 인덱스를 통해 `DEPTNO` 순으로 데이터를 읽어옵니다.
    2.  사용자가 `ORDER BY DEPTNO, ENAME`을 요청했다면, 오라클은 `DEPTNO`가 이미 정렬된 것을 알고 `SORT ORDER BY INCREMENTAL`을 수행합니다.
    3.  `DEPTNO=10`인 데이터들만 모아서 그 안에서 `ENAME`을 정렬하고 바로 결과를 보냅니다. 그 후 `DEPTNO=20`인 데이터로 넘어갑니다.

---

### 💡 핵심 요약 (OCP 포인트)

* **도입 버전:** Oracle 12.2 이상
* **활성화 파라미터:** `_optimizer_incremental_sort` (기본값 TRUE)
* **장점:** 전체 정렬 대기 시간 감소, 메모리 효율화, Top-N 쿼리 최적화.
* **전제 조건:** 선행 정렬 컬럼에 대한 인덱스가 존재하거나 이전 단계에서 정렬이 보장되어야 함.

---
