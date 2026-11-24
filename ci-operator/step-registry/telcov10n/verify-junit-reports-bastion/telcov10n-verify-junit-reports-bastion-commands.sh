#!/bin/bash
set -e
set -o pipefail

if [[ -f "${SHARED_DIR}/skip.txt" ]]; then
  echo "Detected skip.txt — skipping"
  exit 0
fi

echo "Failed" > "${SHARED_DIR}/job_status.txt"
if [[ ! -s "${SHARED_DIR}/bastion_junit_report_dir" ]]; then
  echo "No bastion report directory was recorded" >&2
  exit 1
fi
REPORT_DIR=$(cat "${SHARED_DIR}/bastion_junit_report_dir")

BASTION_IP=$(python3 -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["ansible_host"])' < "${SHARED_DIR}/bastion")
BASTION_USER=$(tr -d '[:space:]' < /var/group_variables/common/all/ansible_user)

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
install -m 0600 /var/group_variables/common/all/ansible_ssh_private_key "${WORK_DIR}/ssh_key"
mkdir "${WORK_DIR}/junit"

echo "Fetch JUnit reports from ${REPORT_DIR} on the bastion"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${WORK_DIR}/ssh_key" \
  "${BASTION_USER}@${BASTION_IP}:${REPORT_DIR}/*.xml" "${WORK_DIR}/junit/"

SHARED_DIR="${WORK_DIR}/junit" python3 /eco-ci-cd/scripts/fail_if_any_test_failed.py
echo "Passed" > "${SHARED_DIR}/job_status.txt"
