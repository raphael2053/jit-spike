#!/bin/bash
set -euo pipefail

REPO_OWNER="luxorlabs"
REPO_NAME="jit-runner-spike"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
TARGET_JOB_ID="${TARGET_JOB_ID:-}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    exit 1
fi

if [ -z "$TARGET_JOB_ID" ]; then
    echo "Error: TARGET_JOB_ID environment variable not set"
    exit 1
fi

echo "Monitoring Job ID: $TARGET_JOB_ID"
echo "Press Ctrl+C to stop monitoring"
echo ""

while true; do
    RESPONSE=$(curl -s \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/jobs/${TARGET_JOB_ID}")
    
    STATUS=$(echo "$RESPONSE" | jq -r '.status')
    CONCLUSION=$(echo "$RESPONSE" | jq -r '.conclusion')
    RUNNER_NAME=$(echo "$RESPONSE" | jq -r '.runner_name')
    STARTED_AT=$(echo "$RESPONSE" | jq -r '.started_at')
    COMPLETED_AT=$(echo "$RESPONSE" | jq -r '.completed_at')
    
    clear
    echo "=========================================="
    echo "Job Monitoring - $(date)"
    echo "=========================================="
    echo "Job ID: $TARGET_JOB_ID"
    echo "Status: $STATUS"
    echo "Conclusion: $CONCLUSION"
    echo "Runner Name: $RUNNER_NAME"
    echo "Started At: $STARTED_AT"
    echo "Completed At: $COMPLETED_AT"
    echo "=========================================="
    
    if [ "$STATUS" = "completed" ]; then
        echo ""
        echo "✅ Job completed!"
        echo "Final conclusion: $CONCLUSION"
        break
    fi
    
    sleep 5
done