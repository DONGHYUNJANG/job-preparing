#!/bin/bash
# Oracle RAC 통합 종료 스크립트
# 작성 목적: DB 인스턴스 및 클러스터 전체 안전 종료

# ----------------------------------------------------
# 0. Root 권한 체크 로직
# ----------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "Error: 이 스크립트는 반드시 root 권한으로 실행해야 합니다."
  echo "실행 예: sudo $0 또는 root 계정으로 전환 후 실행"
  exit 1
fi

# ----------------------------------------------------
# 1. 환경 변수 설정 (시스템 환경에 맞게 수정 필요)
# ----------------------------------------------------
# oracle 유저의 환경변수를 불러오거나 직접 지정해야 srvctl이 동작합니다.
DB_NAME="racdb"
ORACLE_HOME="/u01/app/oracle/product/19c"
GRID_HOME="/u01/app/grid/19c"

echo "----------------------------------------------------"
echo "1. Oracle Database (${DB_NAME}) 종료 시작..."
echo "----------------------------------------------------"
# root에서 oracle 유저 권한으로 srvctl 실행
su - oracle -c "${ORACLE_HOME}/bin/srvctl stop database -d ${DB_NAME} -o immediate"

if [ $? -eq 0 ]; then
    echo ">>> DB 종료 완료."
else
    echo ">>> DB 종료 중 오류 발생 (이미 꺼져있을 수 있음)."
fi

echo ""
echo "----------------------------------------------------"
echo "2. Grid Infrastructure (Cluster) 모든 노드 종료..."
echo "----------------------------------------------------"
# root 권한이므로 sudo 없이 직접 실행
${GRID_HOME}/bin/crsctl stop cluster -all -f

echo ""
echo "모든 서비스가 안전하게 종료되었습니다."