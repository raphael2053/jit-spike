#!/bin/bash
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-raphael2053}"
REPO_NAME="${REPO_NAME:-jit-spike}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
TEST_NAME="${1:-test}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    exit 1
fi

# Generate unique label (timestamp + random)
UNIQUE_LABEL="tenki-$(date +%s)-$(openssl rand -hex 4)"

echo "=========================================="
echo "Dispatching workflow with unique label"
echo "=========================================="
echo "Repository: ${REPO_OWNER}/${REPO_NAME}"
echo "Test Name: ${TEST_NAME}"
echo "Unique Label: ${UNIQUE_LABEL}"
echo ""

# Dispatch workflow with unique label
RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows/test-unique-label.yml/dispatches" \
    -d "{
        \"ref\": \"main\",
        \"inputs\": {
            \"unique_label\": \"${UNIQUE_LABEL}\",
            \"test_name\": \"${TEST_NAME}\"
        }
    }")

# Check for errors
if [ ! -z "$RESPONSE" ]; then
    echo "❌ Error from GitHub API:"
    echo "$RESPONSE" | jq -r '.message' 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

echo "✅ Workflow dispatched successfully!"
echo ""
echo "Next steps:"
echo "1. Wait 2-3 seconds for job to queue"
echo "2. Create runner with this label:"
echo "   export UNIQUE_LABEL=\"${UNIQUE_LABEL}\""
echo "   ./generate-jit-config.sh"
echo "3. Start runner:"
echo "   ./run-jit-runner.sh"
echo ""
echo "To dispatch multiple jobs in parallel:"
echo "  ./dispatch-job-with-label.sh test-1 &"
echo "  ./dispatch-job-with-label.sh test-2 &"
echo "  ./dispatch-job-with-label.sh test-3 &"