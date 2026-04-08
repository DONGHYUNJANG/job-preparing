# AMM 세팅 최적화

[SGA vs PGA 비율 산정 (경험적 가이드)](https://www.notion.so/SGA-vs-PGA-31e0f3217fe8802bab7bcfdf86eec550?pvs=21)

[Oracle AMM (Automatic Memory Management) 설정 및 관리](https://www.notion.so/Oracle-AMM-Automatic-Memory-Management-31e0f3217fe880149ac7ed157abf2a8e?pvs=21)

[📋 Oracle 메모리 최적화 가이드 (AMM 50/60 전략)](https://www.notion.so/Oracle-AMM-50-60-31e0f3217fe88046a38fc1e053de2a34?pvs=21)

[free -h 의 컬럼값과 sga_target, pga_target값의 관계](https://www.notion.so/free-h-sga_target-pga_target-31f0f3217fe8804dadc6de4503b58baa?pvs=21)

```jsx
#!/bin/bash

# ==============================================================================
# Oracle Memory Configuration Helper
# 목적: AMM(Automatic Memory Management) 설정을 통한 최적의 메모리 관리 및 안전성 확보
# 전략: 보수적 운영을 위한 50/60 전략 (Target 50% / Max 60%)
# ==============================================================================

# 전체 메모리 정보 추출 (MB 단위)
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')

# 50/60 전략 계산 (보수적 운영)
# MEMORY_TARGET: 전체 메모리의 50% (안정성 극대화)
# MEMORY_MAX_TARGET: 전체 메모리의 60% (확장 예비 공간)
TARGET_50=$(echo "$TOTAL_MEM * 0.5" | bc | cut -d. -f1)
TARGET_60=$(echo "$TOTAL_MEM * 0.6" | bc | cut -d. -f1)

# PGA_AGGREGATE_LIMIT 계산 (보수적 방어선: Target의 20%의 1.5배)
PGA_ESTIMATED=$(echo "$TARGET_50 * 0.2" | bc | cut -d. -f1)
PGA_LIMIT=$(echo "$PGA_ESTIMATED * 1.5" | bc | cut -d. -f1)

# /dev/shm 현재 크기 확인 (MB 단위)
SHM_TOTAL=$(df -m /dev/shm | tail -1 | awk '{print $2}')

echo "=== Oracle Conservative Memory Configuration (50/60) ==="
echo "Total Memory         : ${TOTAL_MEM} MB"
echo "------------------------------------------"
echo "Recommended MEMORY_TARGET (50%)     : ${TARGET_50} MB"
echo "Recommended MEMORY_MAX_TARGET (60%) : ${TARGET_60} MB"
echo "Recommended PGA_AGGREGATE_LIMIT     : ${PGA_LIMIT} MB"
echo "------------------------------------------"
# [CHECK] /dev/shm Status
echo "### [STEP 1] /dev/shm OS Status Check ###"
if [ $SHM_TOTAL -lt $TARGET_60 ]; then
    echo "⚠️  WARNING: /dev/shm (${SHM_TOTAL}MB) is SMALLER than MAX_TARGET (${TARGET_60}MB)."
    echo "    To avoid ORA-00845, please run the following as root:"
    echo "    ------------------------------------------------------"
    echo "    # [Immediate Apply]"
    echo "    mount -o remount,size=${TARGET_60}M /dev/shm"
    echo ""
    echo "    # [Permanent Apply] Edit /etc/fstab"
    echo "    tmpfs   /dev/shm   tmpfs   defaults,size=${TARGET_60}M   0 0"
    echo "    ------------------------------------------------------"
else
    echo "✅  PASS: /dev/shm is sufficient for current configuration."
fi
echo ""

echo "### [STEP 2] Oracle SQL Commands (Run in SQL*Plus) ###"
echo "### 1. 기본 메모리 설정 (재기동 필요) ###"
echo "ALTER SYSTEM SET MEMORY_MAX_TARGET = ${TARGET_60}M SCOPE=SPFILE;"
echo "ALTER SYSTEM SET MEMORY_TARGET = ${TARGET_50}M SCOPE=SPFILE;"
echo "------------------------------------------"
echo "### 2. AMM 설정을 위한 개별 파라미터 0 설정 (재기동 필요) ###"
echo "# [AMM 설정]: 오라클이 자율적으로 관리하도록 개별 영역은 0으로 둡니다."
echo "ALTER SYSTEM SET SHARED_POOL_SIZE = 0 SCOPE=SPFILE;"
echo "ALTER SYSTEM SET DB_CACHE_SIZE = 0 SCOPE=SPFILE;"
echo "ALTER SYSTEM SET LARGE_POOL_SIZE = 0 SCOPE=SPFILE;"
echo "ALTER SYSTEM SET JAVA_POOL_SIZE = 0 SCOPE=SPFILE;"
echo "ALTER SYSTEM SET STREAMS_POOL_SIZE = 0 SCOPE=SPFILE;"
echo "ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 0 SCOPE=SPFILE;"
echo "------------------------------------------"
echo "### 3. 시스템 보호를 위한 방어선 설정 (즉시 적용) ###"
echo "ALTER SYSTEM SET PGA_AGGREGATE_LIMIT = ${PGA_LIMIT}M SCOPE=BOTH;"
echo "------------------------------------------"
echo "### 4. 메모리 구성 확인 쿼리 ###"
echo "# 현재 오라클이 동적으로 할당하여 사용 중인 메모리 컴포넌트 확인"
echo "SELECT component, current_size/1024/1024 as \"Current_MB\" FROM v\$memory_dynamic_components WHERE current_size > 0;"
```