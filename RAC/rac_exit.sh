#!/bin/bash
# Oracle RAC 통합 종료 스크립트 (oracle 유저 실행 권장)

DB_NAME="JDHDB"

echo "----------------------------------------------------"
echo "1. Oracle Database (${DB_NAME}) 종료 시작..."
echo "----------------------------------------------------"
srvctl stop database -d ${DB_NAME} -o immediate

if [ $? -eq 0 ]; then
    echo ">>> DB 종료 완료."
else
    echo ">>> DB 종료 중 오류 발생!"
    exit 1
fi

echo ""
echo "----------------------------------------------------"
echo "2. Grid Infrastructure (Cluster) 모든 노드 종료..."
echo "----------------------------------------------------"
# root 권한이 필요할 수 있으므로, 설정에 따라 sudo 혹은 각 노드에서 실행
# 이 명령어는 모든 노드의 클러스터 스택을 한꺼번에 내립니다.
sudo $GRID_HOME/bin/crsctl stop cluster -all

echo ""
echo "모든 서비스가 안전하게 종료되었습니다."