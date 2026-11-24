#!/bin/bash
set -e
set -o pipefail

if [[ -f "${SHARED_DIR}/skip.txt" ]]; then
  exit 0
fi

PROJECT_DIR=/tmp

echo "Set CLUSTER_NAME env var"
if [[ -f "${SHARED_DIR}/cluster_name" ]]; then
    CLUSTER_NAME=$(cat "${SHARED_DIR}/cluster_name")
fi
export CLUSTER_NAME=${CLUSTER_NAME}
echo CLUSTER_NAME="${CLUSTER_NAME}"

echo "Set bastion ssh configuration"
cat /var/group_variables/common/all/ansible_ssh_private_key > $PROJECT_DIR/temp_ssh_key
chmod 600 $PROJECT_DIR/temp_ssh_key
BASTION_IP=$(cat /var/host_variables/"${CLUSTER_NAME}"/bastion/ansible_host)
BASTION_USER=$(cat /var/group_variables/common/all/ansible_user)

echo "Create artifacts directory"
mkdir "${PROJECT_DIR}"/artifacts

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /tmp/temp_ssh_key)
echo "Fetch Phase 1 artifacts"
scp -r "${SSH_OPTS[@]}" "${BASTION_USER}@${BASTION_IP}":~/build-artifiacts/* "${PROJECT_DIR}/artifacts/"

echo "Gather inventory files"
for file in "${PROJECT_DIR}/artifacts/"*; do
  case "${file##*/}" in
    *.xml|bastion_junit_report_dir) continue ;;
  esac
  cp "${file}" "${SHARED_DIR}/"
done

echo "Stage Phase 1 JUnit reports in the current job's bastion directory"
mkdir -p "${ARTIFACT_DIR}/junit"
shopt -s nullglob
for file in "${PROJECT_DIR}/artifacts/"*.xml; do
  name=${file##*/}
  case "${name}" in
    junit_*.xml) ;;
    # Older Phase 1 runs saved raw downstream suites without a junit_ prefix.
    *_suite_test.xml)
      name="junit_${name}"
      [[ -f "${PROJECT_DIR}/artifacts/${name}" ]] && continue
      ;;
    *) continue ;;
  esac
  cp "${file}" "${ARTIFACT_DIR}/junit/${name}"
done

REPORT_DIR=$(cat "${SHARED_DIR}/bastion_junit_report_dir")
reports=("${ARTIFACT_DIR}"/junit/junit_*.xml)
if (( ${#reports[@]} == 0 )); then
  echo "No Phase 1 JUnit reports found" >&2
  exit 1
fi
ssh "${SSH_OPTS[@]}" "${BASTION_USER}@${BASTION_IP}" mkdir -p -m 0700 "${REPORT_DIR}"
scp "${SSH_OPTS[@]}" "${reports[@]}" "${BASTION_USER}@${BASTION_IP}:${REPORT_DIR}/"
