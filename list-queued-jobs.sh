#!/bin/bash
set -euo pipefail

REPO_OWNER="luxorlabs"
REPO_NAME="jit-runner-spike"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    exit 1
fi

echo "Fetching queued workflow runs..."
echo ""

# Get recent workflow runs
RUNS=$(curl -s \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?status=queued&per_page=10")

echo "Queued Runs:"
echo "$RUNS" | jq -r '.workflow_runs[] | "Run ID: \(.id) | Workflow: \(.name) | Status: \(.status)"'
echo ""

# For each run, get its jobs
echo "Fetching job details for each run..."
echo ""

RUN_IDS=$(echo "$RUNS" | jq -r '.workflow_runs[].id')

for RUN_ID in $RUN_IDS; do
    echo "----------------------------------------"
    echo "Run ID: $RUN_ID"
    
    JOBS=$(curl -s \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}/jobs")
    
    echo "$JOBS" | jq -r '.jobs[] | "  Job ID: \(.id)\n  Job Name: \(.name)\n  Status: \(.status)\n  Labels: \(.labels | join(", "))"'
    echo ""
done

echo "=========================================="
echo "Copy a Job ID from above to use for JIT config generation"
echo "Example: export TARGET_JOB_ID=12345678901"