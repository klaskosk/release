#!/bin/bash
set -e
set -o pipefail

echo "Checking if the job should be skipped..."
if [ -f "${SHARED_DIR}/skip.txt" ]; then
  echo "Detected skip.txt file — skipping the job"
  exit 0
fi


echo "Setup pipeline environment"
cd /eco-ci-cd/
export ANSIBLE_REMOTE_TEMP="/tmp"
ansible-playbook ./playbooks/setup-cluster-env.yml --extra-vars "release=${VERSION} dest_directory=${SHARED_DIR} release_age_max_days=${RELEASE_AGE_MAX_DAYS}"
if [[ -f "${SHARED_DIR}/skip.txt" ]]; then
  exit 0
fi

# Each network job stages its XML on the bastion. Phase 2 imports the saved
# Phase 1 results into its own directory before running its suites.
if [[ ! "${BUILD_ID}" =~ ^[0-9]+$ ]]; then
  echo "A numeric BUILD_ID is required to stage network reports" >&2
  exit 1
fi
printf '/tmp/telcov10n-network-junit-%s\n' "${BUILD_ID}" > "${SHARED_DIR}/bastion_junit_report_dir"

echo "Cluster name"
cat ${SHARED_DIR}/cluster_name

echo "OCP primary nic"
cat ${SHARED_DIR}/ocp_nic

echo "OCP secondary nic"
cat ${SHARED_DIR}/secondary_nic
