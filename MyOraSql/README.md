# Oracle Dictionary Quick Scripts (SQL*Plus)

이 폴더의 `.sql` 파일들은 Oracle의 `USER_*` / `DBA_*` 데이터 딕셔너리 뷰를 **SQL*Plus에서 바로 실행**해서, 관리에 자주 필요한 정보만 **짧은 컬럼 네이밍 + 한 화면 출력** 형태로 보여주기 위한 스크립트입니다.

## 1) 실행 방법

1. SQL*Plus 접속
2. 이 폴더에서 실행

선택) 출력 표가 좀 더 깔끔하게 보이게 아래를 먼저 실행할 수 있습니다.

```sql
@_sqlplus_setup.sql
```

예)

```sql
@user_tbs.sql
@user_idx.sql
@dba_tbs.sql
@user_tbs_p.sql
@user_seg.sql
```

### 전체 조회용 `*_f.sql` (파라미터 없음)

필터 없이 **한 번에 전체 결과**만 보고 싶을 때는, 대응하는 `*_f.sql`을 사용합니다.

- **이름 규칙**: 원본이 `user_idx.sql`이면 전체 조회는 `user_idx_f.sql`, `dba_tbs.sql`이면 `dba_tbs_f.sql`
- **동작**: `accept` 프롬프트 없음, `WHERE` 필터 없음(동일 `SELECT`·`ORDER BY`만 실행)
- **대응 파일**(총 26개):  
  `user_cols`, `user_concols`, `user_cons`, `user_idx`, `user_idx_p`, `user_indc`, `user_prog`, `user_seqs`, `user_seg`, `user_tbs`, `user_tbs_p`, `user_trigs`, `user_views` 및  
  `dba_concols`, `dba_cons`, `dba_idx`, `dba_idx_p`, `dba_indc`, `dba_prog`, `dba_seqs`, `dba_seg`, `dba_tbs`, `dba_tbs_p`, `dba_trigs`, `dba_views`, `dba_users` 의 `_f` 버전

예)

```sql
@user_idx_f.sql
@dba_tbs_f.sql
@dba_seqs_f.sql
@dba_users_f.sql
```

원본(파라미터) 스크립트와 `_f` 중 편한 쪽을 선택하면 됩니다.

### 공통 입력 규칙

스크립트는 실행 시 `accept`로 아래 파라미터를 받을 수 있습니다.

- `blank=all` 이면 공백 입력 -> 해당 필터 없이 전체 조회
- 이름 입력은 내부에서 `upper()`로 처리되므로 대/소문자 구분 없이 동작

각 스크립트는 입력된 값으로 `WHERE` 조건을 구성합니다. (스크립트별 파라미터 의미 요약은 아래 참고)

참고: Oracle에서는 빈 문자열과 `NULL` 처리, SQL\*Plus 치환(`&변수`) 조합이 환경에 따라 헷갈릴 수 있어, **무조건 전체 목록**이 필요하면 `*_f.sql` 사용을 권장합니다.

## 1-1) 파라미터(accept) Quick Reference

- `t` : `TABLE_NAME`
- `o` : `OWNER` (DBA 스크립트에서 schema 필터)
- `i` : `INDEX_NAME`
- `c` : `CONSTRAINT_NAME`
- `p` : `PARTITION_NAME`
- `v` : `VIEW_NAME`
- `s` : `SEQUENCE_NAME`
- `sn` : `SEGMENT_NAME` (`user_seg.sql`, `dba_seg.sql`)
- `ty` : `SEGMENT_TYPE` (예: `TABLE`, `INDEX`, `LOBSEGMENT`, `TABLE PARTITION` 등, blank=all)
- `tr` : `TRIGGER_NAME`
- `u` : `USERNAME` (Oracle 계정명, `dba_users.sql` 전용)

## 2) 파일 네이밍 규칙

- `user_*` : 현재 로그인 유저 기준 조회 (`USER_*` 딕셔너리)
- `dba_*` : DBA 범위 조회 (`DBA_*` 딕셔너리)
- `*_f.sql` : 위와 동일 주제의 **전체 조회 전용**(파라미터·필터 없음)

또한 요청한 축약 네이밍을 사용합니다.

- `user_tables`  -> `user_tbs`
- `user_indexes` -> `user_idx`
- `user_tab_columns` -> `user_cols`
- `user_tab_partitions` -> `user_tbs_p`
- `user_ind_partitions` -> `user_idx_p`
- `user_constraints` -> `user_cons`
- `user_cons_columns` -> `user_concols`
- `user_triggers` -> `user_trigs`
- `user_sequences` -> `user_seqs`
- `user_segments` -> `user_seg`
- `user_views` -> `user_views`
- `user_objects` 기반 프로시저/펑션/패키지 -> `user_prog`

`dba_` 버전도 동일하게 대응됩니다. (`dba_segments` -> `dba_seg`)

## 3) 스크립트 목록 & 한 줄 설명

### 입력 파라미터 요약(accept)

- `user_tbs.sql` : `t`(TABLE_NAME, blank=all)
- `user_idx.sql` : `t`(TABLE_NAME, blank=all)
- `user_cols.sql` : `t`(TABLE_NAME, blank=all)
- `user_indc.sql` : `t`(TABLE_NAME), `i`(INDEX_NAME, blank 허용)
- `user_cons.sql` : `t`(TABLE_NAME, blank=all)
- `user_concols.sql` : `t`(TABLE_NAME), `c`(CONSTRAINT_NAME)
- `user_views.sql` : `v`(VIEW_NAME, blank=all)
- `user_seqs.sql` : `s`(SEQUENCE_NAME, blank=all)
- `user_prog.sql` : `p`(OBJECT_NAME, blank=all)
- `user_trigs.sql` : `tr`(TRIGGER_NAME, blank=all)
- `user_tbs_p.sql` : `t`(TABLE_NAME), `p`(PARTITION_NAME)
- `user_idx_p.sql` : `t`(TABLE_NAME), `i`(INDEX_NAME), `p`(PARTITION_NAME)
- `user_seg.sql` : `sn`(SEGMENT_NAME, blank=all), `ty`(SEGMENT_TYPE, blank=all)

- `dba_tbs.sql` : `o`(OWNER), `t`(TABLE_NAME, blank=all)
- `dba_idx.sql` : `o`(OWNER), `t`(TABLE_NAME, blank=all)
- `dba_indc.sql` : `o`(OWNER), `t`(TABLE_NAME), `i`(INDEX_NAME, blank 허용)
- `dba_cons.sql` : `o`(OWNER), `t`(TABLE_NAME), `c`(CONSTRAINT_NAME)
- `dba_concols.sql` : `o`(OWNER), `t`(TABLE_NAME), `c`(CONSTRAINT_NAME)
- `dba_views.sql` : `o`(OWNER), `v`(VIEW_NAME)
- `dba_seqs.sql` : `o`(스키마, `DBA_SEQUENCES.sequence_owner` 기준), `s`(SEQUENCE_NAME, blank=all)
- `dba_prog.sql` : `o`(OWNER), `p`(OBJECT_NAME)
- `dba_trigs.sql` : `o`(OWNER), `tr`(TRIGGER_NAME)
- `dba_tbs_p.sql` : `o`(OWNER), `t`(TABLE_NAME), `p`(PARTITION_NAME)
- `dba_idx_p.sql` : `o`(OWNER), `t`(TABLE_NAME), `i`(INDEX_NAME), `p`(PARTITION_NAME)
- `dba_users.sql` : `u`(USERNAME, blank=all)
- `dba_seg.sql` : `o`(OWNER), `sn`(SEGMENT_NAME, blank=all), `ty`(SEGMENT_TYPE, blank=all)

### User 스크립트 (`USER_*`)

- `user_tbs.sql` : 사용자 테이블 요약 (`USER_TABLES`)
- `user_idx.sql` : 사용자 인덱스 요약 (`USER_INDEXES`)
- `user_cols.sql` : 사용자 테이블 컬럼 요약 (`USER_TAB_COLUMNS`)
- `user_indc.sql` : 사용자 인덱스 컬럼/순서 (`USER_IND_COLUMNS`)
- `user_cons.sql` : 사용자 제약조건 요약 (`USER_CONSTRAINTS`)
- `user_concols.sql` : 제약조건 컬럼/순서 (`USER_CONS_COLUMNS`)
- `user_views.sql` : 사용자 뷰 목록 (`USER_OBJECTS`에서 `VIEW`만)
- `user_seqs.sql` : 사용자 시퀀스 요약 (`USER_SEQUENCES`)
- `user_prog.sql` : 사용자 프로시저/펑션/패키지 목록 (`USER_OBJECTS` 기반)
- `user_trigs.sql` : 사용자 트리거 목록 (`USER_TRIGGERS`)
- `user_tbs_p.sql` : 사용자 테이블 파티션 요약 (`USER_TAB_PARTITIONS`)
- `user_idx_p.sql` : 사용자 인덱스 파티션 요약 (`USER_IND_PARTITIONS`)
- `user_seg.sql` : 사용자 세그먼트 크기/타입 (`USER_SEGMENTS`)

### DBA 스크립트 (`DBA_*`)

- `dba_tbs.sql` : 테이블 요약 (`DBA_TABLES`)
- `dba_idx.sql` : 인덱스 요약 (`DBA_INDEXES`)
- `dba_indc.sql` : 인덱스 컬럼/순서 (`DBA_IND_COLUMNS`)
- `dba_cons.sql` : 제약조건 요약 (`DBA_CONSTRAINTS`)
- `dba_concols.sql` : 제약조건 컬럼/순서 (`DBA_CONS_COLUMNS`)
- `dba_views.sql` : 뷰 목록 (`DBA_OBJECTS`에서 `VIEW`만)
- `dba_seqs.sql` : 시퀀스 요약 (`DBA_SEQUENCES`; 뷰 컬럼은 `SEQUENCE_OWNER`이며 출력 컬럼명은 `owner`로 alias)
- `dba_prog.sql` : 프로시저/펑션/패키지 목록 (`DBA_OBJECTS` 기반)
- `dba_trigs.sql` : 트리거 목록 (`DBA_TRIGGERS`)
- `dba_tbs_p.sql` : 테이블 파티션 요약 (`DBA_TAB_PARTITIONS`)
- `dba_idx_p.sql` : 인덱스 파티션 요약 (`DBA_IND_PARTITIONS`)
- `dba_users.sql` : Oracle 사용자 계정 요약 (`DBA_USERS`; `dba_users_f.sql`은 전체 조회)
- `dba_seg.sql` : 스키마별 세그먼트 크기/타입 (`DBA_SEGMENTS`)

### 추가 스크립트 (sql_temp에서 복사, 비파라미터)

- `free.sql` : `DBA_DATA_FILES` + `DBA_FREE_SPACE`로 테이블스페이스 사용률(Alloc/Used/Free%) 계산
- `i.sql` : `V$INSTANCE`로 인스턴스 이름/상태 조회
- `line.sql` : `V$LOG`로 redo log 그룹별 status/sequence#/archived 조회
- `log.sql` : `V$LOGFILE`로 redo log 파일 멤버 목록 조회
- `logfile.sql` : `DBA_DATA_FILES`로 tablespace_name / file_name 목록 조회
- `ts.sql` : `USER_INDEXES`로 인덱스 메타 조회(이름/타입/테이블/파티션 여부/테이블스페이스)
- `user_ind.sql` : `USER_INDEXES`로 인덱스 메타 조회( `ts.sql`과 용도 유사)

## 4) 출력 포맷 팁

- 모든 스크립트는 `SET LINESIZE`, `COLUMN ... FORMAT`을 지정해서 가능한 한 한 화면에 보이도록 구성했습니다.
- 일부 컬럼(예: 파티션 `HIGH_VALUE`)은 `LONG`/표현식 특성 때문에 `substr()`로 앞부분만 보여주도록 했습니다.

## 5) 에러가 나면

대부분 아래 중 하나입니다.

- 권한 부족: `dba_*` 스크립트는 `DBA_*` 딕셔너리 접근 권한이 필요합니다.
- 컬럼명/뷰 버전 차이: 특정 컬럼이 없는 경우 SQL*Plus에서 에러가 납니다.
- **SQL\*Plus `SP2-0734` (첫 줄 `--` 주석을 명령으로 오인)**: 스크립트가 **UTF-8 BOM**으로 저장된 경우 발생할 수 있습니다. `*_f.sql`은 BOM 없이 저장되도록 맞춰 두었습니다. 에디터에서 “UTF-8 (BOM 없음)”으로 저장하거나, 메모장++·VS Code 등에서 인코딩을 확인하세요.
- **`@이름` 실행 시 `SP2-0310` (파일 없음)**: `@emp`처럼 **확장자 없이** 쓰면 현재 디렉터리의 `emp.sql`을 찾습니다. 이 폴더의 스크립트는 `@user_idx.sql` 또는 `@user_idx` 형태로 실행하세요.

에러 메시지(전체)를 그대로 복사해서 알려주면, 해당 Oracle 버전/스펙에 맞게 컬럼을 조정해줄게요.

