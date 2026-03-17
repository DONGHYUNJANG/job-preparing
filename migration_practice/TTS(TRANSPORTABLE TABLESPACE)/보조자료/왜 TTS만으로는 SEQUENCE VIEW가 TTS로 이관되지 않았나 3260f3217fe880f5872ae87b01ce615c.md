# 왜 TTS만으로는 SEQUENCE / VIEW가 TTS로 이관되지 않았나?

### 1. 객체 저장 위치 차이

- **세그먼트(데이터) 객체**: 테이블스페이스 데이터파일(`ts10000.dbf`)에 저장
    - 예: **TABLE, INDEX, LOB**
- **비세그먼트(딕셔너리) 객체**: 데이터 딕셔너리(SYSTEM 등)에 메타데이터로 저장
    - 예: **VIEW, SEQUENCE, PROCEDURE, FUNCTION, PACKAGE, SYNONYM**

### 2. TTS가 옮기는 범위

TTS는 기본적으로 **데이터파일(dbf)을 복사**하므로, **dbf에 들어있는 세그먼트만** 같이 이동합니다.

```
ts10000.dbf 복사
	└─ 포함: TABLE, INDEX 같은 세그먼트
	└─ 미포함: VIEW, SEQUENCE (딕셔너리 객체)
```

### 3. TRIGGER는 왜 따라왔나?

TTS용 `expdp`는 **필수 메타데이터 일부(테이블 정의/제약/트리거 등)** 를 **덤프(.dmp)** 에 포함시켜 처리합니다.

하지만 **VIEW / SEQUENCE는 Transport Tablespace 모드에서 대표적으로 제외**되어 미이관됩니다.

### 4. 결론(객체별 포함 여부)

- TABLE: dbf ✅ / dmp ✅ → 이관됨
- INDEX: dbf ✅ / dmp ✅ → 이관됨
- CONSTRAINT: dbf ❌ / dmp ✅ → 이관됨
- TRIGGER: dbf ❌ / dmp ✅ → 이관됨(컴파일 오류 가능)
- **SEQUENCE: dbf ❌ / dmp ❌ → 미이관**
- **VIEW: dbf ❌ / dmp ❌ → 미이관**
- PROCEDURE/FUNCTION 등: dbf ❌ / dmp ❌ → 미이관