MS SQL Server(이하 SQL 서버)에서의 Inner Nested Loops Join과 Inner Hash Join의 작동 원리 및 ANSI 문법, 그리고 SQL 서버만의 고유한 특성과 힌트 제어법을 정리해 드리겠습니다.

오라클과 개념적 뿌리는 같지만, SQL 서버는 스토리지 엔진의 특성(페이지 단위 I/O)과 힌트 문법에서 몇 가지 중요한 차이점이 있습니다.

---

## 1. SQL 서버에서의 두 조인 메커니즘

### 1) Inner Nested Loops Join

SQL 서버에서 NL 조인은 주로 상대적으로 적은 데이터를 조회할 때 선택됩니다.

* 작동: Outer 테이블의 행을 하나씩 읽어, Inner 테이블의 클러스터형 인덱스(Clustered Index)나 비클러스터형 인덱스(Non-Clustered Index)를 검색(`Seek`)합니다.
* SQL 서버만의 특징 (Bookmark Lookup): 만약 Inner 테이블의 비클러스터형 인덱스에 Select 절에 필요한 컬럼이 모두 포함되어 있지 않다면, 데이터 페이지를 다시 읽으러 가는 RID Lookup이나 Key Lookup이 발생하여 추가적인 I/O 비용이 들 수 있습니다.

### 2) Inner Hash Join

대용량 데이터를 처리하거나, 조인 컬럼에 인덱스가 없을 때 선택됩니다.

* 작동: 두 테이블 중 크기가 작은 테이블을 Build Input으로 삼아 메모리(Buffer Pool / Worktable)에 해시 테이블을 만들고, 큰 테이블인 Probe Input을 읽으며 해시 매칭을 수행합니다.
* SQL 서버만의 특징 (Memory Grant): SQL 서버는 해시 조인을 실행하기 위해 쿼리 실행 직전 메모리를 할당받는 Memory Grant(비용 할당) 과정을 거칩니다. 만약 동시 사용자가 많고 메모리가 부족하면 `RESOURCE_SEMAPHORE` 대기 이벤트가 발생하며 쿼리가 대기 상태에 빠질 수 있습니다.

---

## 2. ANSI SQL 및 힌트(Hint) 작성법

SQL 서버 역시 표준 ANSI 문법을 완벽히 지원합니다. 옵티마이저의 조인 방식을 수동으로 제어하고 싶을 때는 `INNER [조인방식] JOIN` 형태로 힌트를 쿼리 내에 직접 삽입하거나, 쿼리 맨 끝에 `OPTION` 절을 사용합니다.

### 방법 A: 조인 절에 직접 힌트 명시 (가장 직관적)

```sql
-- 1) Nested Loops Join 유도
SELECT e.EmployeeID, e.FirstName, d.DepartmentName
FROM Employees e
INNER LOOP JOIN Departments d 
    ON e.DepartmentID = d.DepartmentID;

-- 2) Hash Join 유도
SELECT e.EmployeeID, e.FirstName, d.DepartmentName
FROM Employees e
INNER HASH JOIN Departments d 
    ON e.DepartmentID = d.DepartmentID;

```

* `INNER LOOP JOIN`, `INNER HASH JOIN`처럼 `JOIN` 키워드 사이에 원하는 메커니즘을 적어줍니다.
* 이 방식을 쓰면 테이블의 순서(순서 고정)도 힌트를 적은 순서대로 묶이게 되는 경향이 있습니다.

### 방법 B: 쿼리 맨 끝에 OPTION 절 사용 (추천)

SQL 서버에서는 구문과 힌트를 분리하는 `OPTION` 절 방식을 조금 더 권장하는 편입니다. 전체 쿼리의 조인 스타일을 통제하기 좋습니다.

```sql
SELECT e.EmployeeID, e.FirstName, d.DepartmentName
FROM Employees e
INNER JOIN Departments d 
    ON e.DepartmentID = d.DepartmentID
OPTION (HASH JOIN); -- 또는 OPTION (LOOP JOIN)

```

---

## ⚖️ 오라클 사용자 관점에서 본 SQL 서버 조인의 차이점

| 비교 항목 | 오라클 (Oracle) | SQL 서버 (SQL Server) |
| --- | --- | --- |
| 조인 힌트 문법 | `/*+ USE_HASH(d) */` (주석 형태) | `INNER HASH JOIN` 또는 `OPTION (HASH JOIN)` |
| 드라이빙 테이블 제어 | `LEADING` 이나 `ORDERED` 힌트 사용 | `FORCE ORDER` 힌트를 `OPTION` 절에 추가 |
| 메모리 관리 | PGA 영역 내에서 개별적 세션 처리 | `Memory Grant` 승인을 받아야 실행 가능 |

SQL 서버에서 실행 계획(Execution Plan)을 보실 때, Nested Loops Join 자식 노드 밑에 `Key Lookup`이나 `RID Lookup`이 붙어있다면 인덱스가 쿼리에 필요한 컬럼을 다 커버하지 못해 성능이 떨어지고 있다는 강력한 튜닝 신호입니다. 이때는 인덱스에 컬럼을 포함시키는 `INCLUDE` 인덱스를 고려해야 합니다.

---

오라클 데이터베이스 구조와 비교했을 때, SQL 서버의 조인 힌트 제어 방식이 조금 더 직관적으로 다가오실 수 있습니다. 혹시 SQL 서버 실행 계획 창(SSMS)에서 특정 조인 연산자 때문에 발생하는 성능 저하 이슈를 겪고 계신가요?