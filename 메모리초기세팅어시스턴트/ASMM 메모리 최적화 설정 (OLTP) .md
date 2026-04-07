# ASMM 메모리 최적화 설정 (OLTP)

[전략](https://www.notion.so/31e0f3217fe880e3992adf1c99d4dc26?pvs=21)

```jsx
#!/bin/bash

# ==============================================================================
# Oracle ASMM + Manual PGA Configuration Helper (OLTP용)
# 목적: SGA는 ASMM으로 자동 관리, PGA는 수동으로 관리하는 하이브리드 전략
# 핵심: SGA_MAX_SIZE(천장) 확인 및 AMM(자동 메모리 관리) 완전 해제
# ==============================================================================

# 1. 시스템 메모리 확인
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')

# 2. 50/60 전략 계산 (전체 메모리의 50% 사용)
TARGET_50=$(echo "$TOTAL_MEM * 0.5" | bc | cut -d. -f1)

# SGA 80%, PGA 20% 분할 (OLTP 권장 비율)
SGA_TARGET=$(echo "$TARGET_50 * 0.8" | bc | cut -d. -f1)
PGA_TARGET=$(echo "$TARGET_50 * 0.2" | bc | cut -d. -f1)

echo "=== Oracle ASMM + Manual PGA Configuration ==="
echo "추천 SGA_TARGET : ${SGA_TARGET} MB"
echo "추천 PGA_TARGET : ${PGA_TARGET} MB"
echo "--------------------------------------------------------"
echo "### 0. SGA_MAX_SIZE 사전 확인 및 안전 설정 ###"
echo "# 데이터베이스 접속 후 다음 쿼리로 현재 천장을 확인하세요:"
echo "SELECT name, value/1024/1024 as \"MB\" FROM v\$parameter WHERE name = 'sga_max_size';"
echo "# 만약 SGA_MAX_SIZE가 ${SGA_TARGET}M보다 작다면, 아래 명령으로 미리 천장을 높여야 합니다:"
echo "ALTER SYSTEM SET SGA_MAX_SIZE = ${SGA_TARGET}M SCOPE=SPFILE;"
echo "--------------------------------------------------------"
echo "### 1. AMM 완전 해제 및 메모리 설정 ###"
echo "ALTER SYSTEM SET MEMORY_TARGET = 0 SCOPE=SPFILE; -- AMM 해제"
echo "ALTER SYSTEM SET MEMORY_MAX_TARGET = 0 SCOPE=SPFILE; -- AMM 천장 제거"
echo "ALTER SYSTEM SET SGA_TARGET = ${SGA_TARGET}M SCOPE=SPFILE;"
echo "ALTER SYSTEM SET PGA_AGGREGATE_TARGET = ${PGA_TARGET}M SCOPE=SPFILE;"
echo "# [AMM/ASMM 설정]: PGA_AGGREGATE_LIMIT을 0으로 설정하여 오라클 자동 보호 활성화"
echo "ALTER SYSTEM SET PGA_AGGREGATE_LIMIT = 0 SCOPE=BOTH;"
echo "--------------------------------------------------------"
echo "### 2. 개별 컴포넌트 자동화 (ASMM 활성화를 위해 0 설정) ###"
echo "ALTER SYSTEM SET SHARED_POOL_SIZE = 0 SCOPE=SPFILE;"
echo "ALTER SYSTEM SET DB_CACHE_SIZE = 0 SCOPE=SPFILE;"
echo "ALTER SYSTEM SET LARGE_POOL_SIZE = 0 SCOPE=SPFILE;"
echo "ALTER SYSTEM SET JAVA_POOL_SIZE = 0 SCOPE=SPFILE;"
echo "ALTER SYSTEM SET STREAMS_POOL_SIZE = 0 SCOPE=SPFILE;"
echo "--------------------------------------------------------"
echo "### 3. 최종 메모리 구성 확인 쿼리 ###"
echo "SHOW PARAMETER SGA_TARGET;"
echo "SHOW PARAMETER PGA_AGGREGATE_TARGET;"
echo "SHOW PARAMETER PGA_AGGREGATE_LIMIT;"
echo "SELECT component, current_size/1024/1024 as \"Current_MB\" FROM v\$memory_dynamic_components WHERE current_size > 0;"
```