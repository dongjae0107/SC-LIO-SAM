#!/bin/bash
set -euo pipefail

source ../../../devel/setup.bash


# ===== Input argument =====
if [ $# -lt 1 ]; then
  echo "Usage: $0 <dataset_name>"
  echo "Example: $0 303_2"
  exit 1
fi

DATASET=$1
BAG="/workspace/Dataset/${DATASET}/dataset.bag"
GT="/workspace/Dataset/${DATASET}/groundtruth.txt"

# 1) lio_sam launch (독립 프로세스 그룹으로 실행)
setsid roslaunch lio_sam run_steam.launch > lio_sam.log 2>&1 &
LIO_PID=$!
LIO_PGID=$LIO_PID
echo "[INFO] Launched lio_sam (PID: $LIO_PID, PGID: $LIO_PGID)"
sleep 3   # 노드 준비 시간

# 2) rosbag 실행 (출력 숨김)
rosbag play "$BAG" --topics /ouster/points /imu > /dev/null 2>&1
echo "[INFO] rosbag finished."

# rosbag 끝난 후 5초 대기 → lio_sam 종료
sleep 5

# 점진적 종료 함수
graceful_kill_group () {
  local pgid=$1
  local name=$2
  local wait_sec=$3
  if kill -0 -"$pgid" 2>/dev/null; then
    echo "Sending SIGINT to $name (PGID: $pgid)"
    kill -INT -"$pgid" 2>/dev/null || true
    for ((i=0; i<wait_sec; i++)); do
      if kill -0 -"$pgid" 2>/dev/null; then sleep 1; else break; fi
    done
  fi
  if kill -0 -"$pgid" 2>/dev/null; then
    echo "Still alive. Sending SIGTERM to $name"
    kill -TERM -"$pgid" 2>/dev/null || true
    sleep 2
  fi
  if kill -0 -"$pgid" 2>/dev/null; then
    echo "Still alive. Sending SIGKILL to $name"
    kill -KILL -"$pgid" 2>/dev/null || true
  fi
}

graceful_kill_group "$LIO_PGID" "lio_sam" 10
echo "[INFO] lio_sam terminated."

# 3) evo_ape 실행 → RMSE만 출력
RESULT=$(evo_ape tum /workspace/Dataset/output/estimate.txt "$GT" -va | awk '/^[[:space:]]*rmse[[:space:]]/ {print $2; exit}')
echo "The trajectory absolute translation error is $RESULT meter"

