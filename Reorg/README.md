# Oracle Table Reorganization Scripts for 'SH' Schema

## 1. 개요

이 스크립트 모음은 Oracle 데이터베이스의 **SH** 스키마에 포함된 일반 테이블과 인덱스를 재구성(Reorganization)하기 위해 생성되었습니다. 테이블을 재구성하면 단편화를 제거하여 공간을 효율적으로 사용하고 쿼리 성능을 향상시킬 수 있습니다.

---
> **‼️ 매우 중요: 경고 ‼️**
>
> *   **사전 백업 필수**: 이 작업을 실행하기 전에는 **반드시 데이터베이스 전체 백업(Full Backup)을 받아야 합니다.**
> *   **서비스 영향**: 이 작업은 시스템에 상당한 부하를 유발하므로, 사용량이 가장 적은 시간(비 피크 타임)에 실행해야 합니다.
> *   **대상 테이블**: 이 스크립트는 **파티션(Partition), IOT(Index-Organized Table), LOB 세그먼트를 포함한 특수 테이블을 제외한 일반 테이블**만을 대상으로 합니다. 해당 객체들은 별도의 작업이 필요합니다.
---

## 2. 생성된 파일 목록

*   `reorg_pre_check.sql`
    *   Reorg 작업을 시작하기 전 시스템 자원(CPU, Undo, Archive, PGA)이 충분한지 확인하는 진단용 SQL 스크립트입니다.
*   `reorg_set_nologging.sql`
    *   `SH` 스키마의 일반 테이블들을 `NOLOGGING` 모드로 변경하는 SQL 문을 생성합니다. (`reorg_set_nologging_run.sql` 파일 생성)
*   `reorg_set_logging.sql`
    *   `SH` 스키마의 일반 테이블들을 다시 `LOGGING` 모드로 원복하는 SQL 문을 생성합니다. (`reorg_set_logging_run.sql` 파일 생성)
*   `reorg_execute.sh`
    *   테이블 재구성(`MOVE`)과 인덱스 재빌드(`REBUILD`)를 병렬로 실행하는 메인 셸 스크립트입니다.

## 3. 전체 작업 시나리오 (실행 순서)

아래 순서를 반드시 지켜서 작업을 진행하십시오.

### **1단계: 셸 스크립트 환경 설정**

가장 먼저, 메인 실행 스크립트인 `reorg_execute.sh` 파일을 열어 사용자 환경에 맞게 **상단 설정 부분**을 수정합니다.

```bash
# reorg_execute.sh

# ---[ 1. User Configuration ]-------------------------------------------------
# !! Set your environment and connection details !!
export ORACLE_SID="ORCL"                  # Your Oracle SID
export ORACLE_HOME="/u01/app/oracle/product/19c/dbhome_1" # Your Oracle Home

# -- Connection (Option 2: User/Password)
SQLPLUS_USER="system"
SQLPLUS_PASS="your_password" # 실제 패스워드로 변경
SQLPLUS_CONN="${SQLPLUS_USER}/${SQLPLUS_PASS}"

# -- Target Schema and Parallelism
SCHEMA_NAME="SH"
DOP=4  # 병렬처리 수준, reorg_pre_check.sql 결과의 CPU_COUNT 값을 참고하여 조정
```

### **2단계: 사전 체크**

DBA 권한으로 SQL*Plus에 접속하여 `reorg_pre_check.sql`를 실행하고, 그 결과를 바탕으로 작업 가능 여부를 판단합니다.

```sql
-- SQL*Plus에서 실행
@reorg_pre_check.sql
```
*   **확인 사항**: Undo, Archive 공간이 충분한지, CPU 사용률이 너무 높지 않은지 등을 반드시 확인합니다. 자원이 부족하면 작업을 진행해서는 안 됩니다.

### **3단계: 사전 백업 (RMAN)**

만일의 사태에 대비하여 RMAN으로 전체 백업을 수행합니다.

```bash
# 터미널에서 실행
rman target /

# RMAN 프롬프트에서 실행
RMAN> RUN {
RMAN>   BACKUP DATABASE PLUS ARCHIVELOG DELETE INPUT;
RMAN> }
```

### **4단계: NOLOGGING 모드 설정**

Reorg 작업 속도 향상을 위해 테이블을 `NOLOGGING` 모드로 변경합니다.

1.  SQL*Plus에서 `reorg_set_nologging.sql` 스크립트를 실행하여 변경 스크립트를 생성합니다.
    ```sql
    @reorg_set_nologging.sql
    ```
2.  위 명령을 실행하면 현재 폴더에 `reorg_set_nologging_run.sql` 파일이 생성됩니다. 내용을 검토한 후, 이 파일을 실행하여 실제 변경을 적용합니다.
    ```sql
    @reorg_set_nologging_run.sql
    ```

### **5단계: Reorg 실행**

터미널(셸)에서 `reorg_execute.sh` 스크립트를 실행합니다. 작업 내용은 `reorg_execute_*.log` 파일에 기록됩니다.

```bash
# 터미널에서 실행 권한 부여
chmod +x reorg_execute.sh

# 스크립트 실행
./reorg_execute.sh
```

### **6단계: LOGGING 모드 원복**

작업이 완료되면 모든 테이블을 다시 `LOGGING` 모드로 되돌립니다.

1.  SQL*Plus에서 `reorg_set_logging.sql` 스크립트를 실행하여 원복 스크립트를 생성합니다.
    ```sql
    @reorg_set_logging.sql
    ```
2.  위 명령을 실행하면 `reorg_set_logging_run.sql` 파일이 생성됩니다. 이 파일을 실행하여 원복을 적용합니다.
    ```sql
    @reorg_set_logging_run.sql
    ```

### **7단계: 최종 백업 (RMAN)**

모든 작업이 완료되었으므로, 변경된 데이터베이스 상태를 기준으로 다시 한번 전체 백업을 수행합니다.

```bash
# 터미널에서 실행
rman target /

# RMAN 프롬프트에서 실행
RMAN> RUN {
RMAN>   BACKUP DATABASE PLUS ARCHIVELOG DELETE INPUT;
RMAN> }
```

---
이것으로 모든 작업이 완료됩니다.
