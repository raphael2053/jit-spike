#!/bin/bash
set -euo pipefail

REPO_OWNER="raphael2053"
REPO_NAME="jit-spike"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    exit 1
fi

echo "Queueing test jobs..."
echo "Note: These jobs will wait for a runner with label 'jit-spike'"
echo ""

# Trigger the test workflows
WORKFLOWS=("test-job-1.yml" "test-job-2.yml" "test-job-3.yml")

for workflow in "${WORKFLOWS[@]}"; do
    echo "Triggering workflow: $workflow"
    
    RESPONSE=$(curl -s -w "%{http_code}" \
      -X POST \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/workflows/$workflow/dispatches" \
      -d '{"ref":"main"}')
    
    HTTP_CODE="${RESPONSE: -3}"
    
    if [ "$HTTP_CODE" -eq 204 ]; then
        echo "  ✓ Successfully triggered $workflow"
    else
        echo "  ✗ Failed to trigger $workflow (HTTP $HTTP_CODE)"
        echo "  Response: ${RESPONSE%???}"
    fi
    
    # Small delay between requests
    sleep 1
done

echo ""
echo "All workflows triggered. Use './list-queued-jobs.sh' to see queued jobs."
echo "Use './monitor-job.sh <job-id>' to monitor a specific job."