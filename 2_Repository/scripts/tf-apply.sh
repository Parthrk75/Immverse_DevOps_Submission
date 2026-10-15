#!/usr/bin/env bash
# Two-phase apply (cluster first, then helm-based platform). Usage: scripts/tf-apply.sh infra/stacks/shared-eu-aws
set -euo pipefail
dir="${1:?stack dir}"
terraform -chdir="$dir" init -input=false
terraform -chdir="$dir" apply -input=false -auto-approve -target=module.provider
terraform -chdir="$dir" apply -input=false -auto-approve
