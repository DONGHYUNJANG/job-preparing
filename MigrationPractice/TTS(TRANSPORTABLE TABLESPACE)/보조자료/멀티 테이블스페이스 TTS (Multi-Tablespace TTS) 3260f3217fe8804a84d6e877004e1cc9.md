# 멀티 테이블스페이스 TTS (Multi-Tablespace TTS)

---

TTS는 **"이동하려는 테이블스페이스 세트가 그 자체로 완벽한 논리적 덩어리인가"**를 중요하게 생각합니다. 데이터가 A에 있고 인덱스가 B에 있다면, A와 B는 하나의 세트로 취급되어야 합니다.

---

## 🛠 문제 해설: 올바른 실행 방법

사용자님이 작성하신 쿼리를 아래와 같이 수정해서 실행해야 합니다.

### 1. 체크 단계 (두 곳 모두 포함)

먼저 두 테이블스페이스가 서로를 참조하고 있는지 확인합니다.

```jsx
- 테이블스페이스가 ts10000(데이터), ts10000_idx(인덱스)라고 가정할 때
EXEC DBMS_TTS.TRANSPORT_SET_CHECK('ts10000, ts10000_idx', TRUE);
- 위반 사항이 없는지 확인
SELECT  FROM TRANSPORT_SET_VIOLATIONS;
```

### 2. Export 실행 (한 번에 수행)

`tablespaces` 옵션에 이관할 모든 테이블스페이스명을 나열합니다.

```jsx
expdp directory=datapump_dir \
      dumpfile=ts10000_full.dmp \
      transport_tablespace=y \
      tablespaces=ts10000, ts10000_idx
```

### 3. Import 실행 (두 데이터파일 모두 지정)

가장 중요한 부분입니다. 타겟 DB로 넘길 때 **두 개의 데이터파일 경로를 모두** 알려줘야 합니다.

```jsx
impdp directory=datapump_dir \
      dumpfile=ts10000_full.dmp \
      transport_datafiles='/path/to/ts10000.dbf', '/path/to/ts10000_idx.dbf' \
      remap_schema=hr:hr2
```