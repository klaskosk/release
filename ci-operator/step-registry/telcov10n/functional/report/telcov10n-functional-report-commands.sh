#!/bin/bash
set -e
set -o pipefail

ECO_CI_CD_INVENTORY_PATH="/eco-ci-cd/inventories/cnf"

echo "Checking if the job should be skipped..."
if [ -f "${SHARED_DIR}/skip.txt" ]; then
  echo "Detected skip.txt — skipping"
  exit 0
fi

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

echo "Remove report directories"
rm -rf /tmp/reports

echo "Create reports directory"
mkdir -pv /tmp/reports

# Reports are either staged in SHARED_DIR by the test steps or produced on the
# bastion by the lane's plays. Either way Report Portal gets a single report set.
#
# Only the Ginkgo suite JUnit XMLs are that set. report_testrun.xml is a lossy
# aggregate of the same specs, so the report_*/polarion_* copies of it are never
# uploaded even when a lane still stages them.
reports_in_shared_dir=false
for f in "${SHARED_DIR}"/*polarion*.xml "${SHARED_DIR}"/report_*.xml "${SHARED_DIR}"/junit_*.xml; do
  if [[ -f "$f" ]]; then
    reports_in_shared_dir=true
    break
  fi
done

if [[ "${reports_in_shared_dir}" == "false" ]]; then
  echo "No Reports found in ${SHARED_DIR}, Using Bastion"
  BASTION_REPORT_DIR="/tmp/test_reports"
  # The lane's plays stage a single suite JUnit set on the bastion. Lanes whose
  # reports live elsewhere (e.g. O-RAN) set JUNIT_REPORT_DIR in their job config,
  # so honour that value when it is present.
  JUNIT_REPORT_DIR="${JUNIT_REPORT_DIR:-${BASTION_REPORT_DIR}/junit}"
  processed_report_dir="${JUNIT_REPORT_DIR}"
  UPLOAD_SHARED_DIR=""
else
  echo "Reports found in SHARED_DIR"
  for f in "${SHARED_DIR}"/junit_*.xml; do
    if [[ -f "$f" ]]; then
      filename=$(basename "$f" | sed 's/^junit_//')
      cp "$f" "/tmp/reports/${filename}"
    fi
  done
  processed_report_dir="/tmp/reports"
  UPLOAD_SHARED_DIR="${SHARED_DIR}"
fi

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

echo "Uploading reports from ${processed_report_dir} to Report Portal"
SHARED_DIR="${UPLOAD_SHARED_DIR}" ansible-playbook ./playbooks/upload-report.yaml \
  -i ./inventories/cnf/switch-config.yaml \
  --extra-vars "kubeconfig=${KUBECONFIG} \
    reporter_template_name='${REPORTER_TEMPLATE_NAME}' \
    processed_report_dir='${processed_report_dir}' \
    reports_directory=/tmp/upload \
    reporter_launch_name='${REPORTER_LAUNCH_NAME}' \
    upload_to_report_portal=${UPLOAD_TO_REPORT_PORTAL} \
    report_portal_url_filename='${REPORTPORTAL_FILES}' \
    reports_portal_attributes='${REPORTS_PORTAL_ATTRIBUTES}'"
