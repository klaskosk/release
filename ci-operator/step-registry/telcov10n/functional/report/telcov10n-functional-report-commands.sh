#!/bin/bash
set -e
set -o pipefail

ECO_CI_CD_INVENTORY_PATH="/eco-ci-cd/inventories/cnf"

echo "Checking if the job should be skipped..."
if [ -f "${SHARED_DIR}/skip.txt" ]; then
  echo "Detected skip.txt — skipping"
  exit 0
fi

if [[ ! -s "${SHARED_DIR}/bastion_junit_report_dir" ]]; then
  echo "No bastion report directory was recorded — skipping upload"
  exit 0
fi
REPORT_DIR=$(cat "${SHARED_DIR}/bastion_junit_report_dir")

echo "Create group_vars directory"
mkdir -pv "${ECO_CI_CD_INVENTORY_PATH}/group_vars"

echo "Copy group inventory files"
# shellcheck disable=SC2154
cp "${SHARED_DIR}/all" "${ECO_CI_CD_INVENTORY_PATH}/group_vars/all"
cp "${SHARED_DIR}/bastions" "${ECO_CI_CD_INVENTORY_PATH}/group_vars/bastions"

echo "Create host_vars directory"
mkdir -pv "${ECO_CI_CD_INVENTORY_PATH}/host_vars"

echo "Copy host inventory files"
cp "${SHARED_DIR}/bastion" "${ECO_CI_CD_INVENTORY_PATH}/host_vars/bastion"

echo "Set CLUSTER_NAME env var"
if [[ -f "${SHARED_DIR}/cluster_name" ]]; then
    CLUSTER_NAME=$(cat "${SHARED_DIR}/cluster_name")
fi

export CLUSTER_NAME="${CLUSTER_NAME}"
echo "CLUSTER_NAME=${CLUSTER_NAME}"

KUBECONFIG="/home/telcov10n/project/generated/${CLUSTER_NAME}/auth/kubeconfig"

cd /eco-ci-cd

# Launches are version-qualified so different OCP versions do not collide in
# Report Portal, but the metrics ci_lane attribute must stay versionless.
CI_LANE="${REPORTER_LAUNCH_NAME%-[0-9]*.[0-9]*}"

METRICS_FILE="/tmp/metrics/metrics.txt"

echo "Collecting metrics"
ansible-playbook ./playbooks/collect-metrics.yml \
  -i ./inventories/cnf/switch-config.yaml \
  --extra-vars "kubeconfig=${KUBECONFIG} \
    ci_lane='${CI_LANE}' \
    output_file=${METRICS_FILE} \
    metrics_list=${METRICS_LIST}" || true

REPORTS_PORTAL_ATTRIBUTES=""
if [[ -f "${METRICS_FILE}" ]]; then
  REPORTS_PORTAL_ATTRIBUTES="$(cat "${METRICS_FILE}")"
  echo "REPORTS_PORTAL_ATTRIBUTES: ${REPORTS_PORTAL_ATTRIBUTES}"
fi

# An empty SHARED_DIR tells upload-report.yaml to read from the bastion.
echo "Uploading reports from ${REPORT_DIR} to Report Portal"
SHARED_DIR="" ansible-playbook ./playbooks/upload-report.yaml \
  -i ./inventories/cnf/switch-config.yaml \
  --extra-vars "kubeconfig=${KUBECONFIG} \
    reporter_template_name='${REPORTER_TEMPLATE_NAME}' \
    processed_report_dir='${REPORT_DIR}' \
    reports_directory=/tmp/upload \
    reporter_launch_name='${REPORTER_LAUNCH_NAME}' \
    upload_to_report_portal=${UPLOAD_TO_REPORT_PORTAL} \
    report_portal_url_filename='${REPORTPORTAL_FILES}' \
    reports_portal_attributes='${REPORTS_PORTAL_ATTRIBUTES}'"

case "${UPLOAD_TO_REPORT_PORTAL,,}" in
  true|yes|on|1) touch "${SHARED_DIR}/report_portal_uploaded" ;;
esac
