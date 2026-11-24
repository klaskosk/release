#!/bin/bash
set -e
set -o pipefail

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

echo "Store content from phase 1 run in SHARED_DIR"
scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /tmp/temp_ssh_key "${BASTION_USER}@${BASTION_IP}":~/build-artifiacts/* "${PROJECT_DIR}"/artifacts/

echo "Gather inventory files"
for file in "${PROJECT_DIR}"/artifacts/*; do
  [[ "$file" == *.xml ]] && continue
  cp "${file}" "${SHARED_DIR}"/
done

echo "Copy suite JUnit reports for reporter step"
for file in "${PROJECT_DIR}"/artifacts/junit_*.xml; do
  [[ -f "$file" ]] || continue
  cp "${file}" "${SHARED_DIR}"/
done

# The report_*.xml aggregates are ignored: Report Portal gets the suite JUnit
# set only.
mkdir "${ARTIFACT_DIR}/junit"
for file in "${PROJECT_DIR}"/artifacts/*.xml; do
  case "$(basename "$file")" in
    report_*.xml) continue ;;
  esac
  echo "${file}"
  cp "${file}" "${ARTIFACT_DIR}"/junit/
done
