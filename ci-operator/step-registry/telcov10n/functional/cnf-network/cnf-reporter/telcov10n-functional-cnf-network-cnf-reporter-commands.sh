#!/bin/bash
set -e
set -o pipefail

ECO_CI_CD_INVENTORY_PATH="/eco-ci-cd/inventories/cnf"

echo "Checking if the job should be skipped..."
if [ -f "${SHARED_DIR}/skip.txt" ]; then
  echo "Detected skip.txt file — skipping the job"
  exit 0
fi

if [[ ! -s "${SHARED_DIR}/bastion_junit_report_dir" ]]; then
  echo "No bastion report directory was recorded — skipping upload"
  exit 0
fi
REPORT_DIR=$(cat "${SHARED_DIR}/bastion_junit_report_dir")

echo "Create group_vars directory"
mkdir "${ECO_CI_CD_INVENTORY_PATH}/group_vars"

echo "Copy group inventory files"
# shellcheck disable=SC2154
cp "${SHARED_DIR}/all" "${ECO_CI_CD_INVENTORY_PATH}/group_vars/all"
cp "${SHARED_DIR}/bastions" "${ECO_CI_CD_INVENTORY_PATH}/group_vars/bastions"

echo "Create host_vars directory"
mkdir "${ECO_CI_CD_INVENTORY_PATH}/host_vars"

echo "Copy host inventory files"
cp "${SHARED_DIR}/bastion" "${ECO_CI_CD_INVENTORY_PATH}/host_vars/bastion"

echo "Set CLUSTER_NAME env var"
if [[ -f "${SHARED_DIR}/cluster_name" ]]; then
    CLUSTER_NAME=$(cat "${SHARED_DIR}/cluster_name")
fi

export CLUSTER_NAME="${CLUSTER_NAME}"
echo CLUSTER_NAME="${CLUSTER_NAME}"

echo "Upload reports"
cd /eco-ci-cd
# shellcheck disable=SC2154
# An empty SHARED_DIR tells upload-report.yaml to read from the bastion.
SHARED_DIR="" ansible-playbook ./playbooks/upload-report.yaml -i ./inventories/cnf/switch-config.yaml \
    --extra-vars "kubeconfig=/home/telcov10n/project/generated/${CLUSTER_NAME}/auth/kubeconfig \
        reporter_template_name='${REPORTER_TEMPLATE_NAME}' processed_report_dir='${REPORT_DIR}' \
        report_portal_url_filename='${REPORTPORTAL_FILES}' \
        reports_directory=/tmp/upload"

touch "${SHARED_DIR}/report_portal_uploaded"
