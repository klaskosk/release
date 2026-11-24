#!/bin/bash
set -e
set -o pipefail
PROJECT_DIR="/tmp"

echo "Checking if the job should be skipped..."
if [ -f "${SHARED_DIR}/skip.txt" ]; then
  echo "Detected skip.txt file — skipping the job"
  exit 0
fi

echo "Set bastion ssh configuration"
grep ansible_ssh_private_key -A 100 "${SHARED_DIR}/all" \
  | sed -e 's/ansible_ssh_private_key: //g' -e "s/'//g" \
  > "${PROJECT_DIR}/temp_ssh_key"
chmod 600 "${PROJECT_DIR}"/temp_ssh_key
BASTION_IP=$(grep -oP '(?<=ansible_host: ).*' "${SHARED_DIR}/bastion" | sed "s/'//g")
BASTION_USER=$(grep -oP '(?<=ansible_user: ).*' "${SHARED_DIR}/all" | sed "s/'//g")

echo "Store Phase 1 build ID"
echo "${BUILD_ID}" > "${SHARED_DIR}/phase1_build_id"

REPORT_DIR=$(cat "${SHARED_DIR}/bastion_junit_report_dir")
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /tmp/temp_ssh_key)
echo "Save the Phase 1 JUnit reports for Phase 2"
ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 \
    "${SSH_OPTS[@]}" "${BASTION_USER}@${BASTION_IP}" \
    "rm -rf ~/build-artifiacts && mkdir -m 0700 ~/build-artifiacts && cp '${REPORT_DIR}'/*.xml ~/build-artifiacts/"

echo "Save the Phase 1 inventory and metadata"
phase1_files=()
for file in "${SHARED_DIR}"/*; do
    if [[ "${file##*/}" != bastion_junit_report_dir ]]; then
        phase1_files+=("${file}")
    fi
done
scp -r "${SSH_OPTS[@]}" "${phase1_files[@]}" "${BASTION_USER}@${BASTION_IP}":~/build-artifiacts/
