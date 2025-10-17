#!/bin/bash
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-raphael2053}"
REPO_NAME="${REPO_NAME:-jit-spike}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
UNIQUE_LABEL="${UNIQUE_LABEL:-}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    exit 1
fi

if [ -z "$UNIQUE_LABEL" ]; then
    echo "Error: UNIQUE_LABEL environment variable not set"
    echo "Example: export UNIQUE_LABEL=\"tenki-1697543210-abc123\""
    exit 1
fi

RUNNER_NAME="runner-${UNIQUE_LABEL}"

echo "=========================================="
echo "Generating JIT configuration"
echo "=========================================="
echo "Repository: ${REPO_OWNER}/${REPO_NAME}"
echo "Unique Label: ${UNIQUE_LABEL}"
echo "Runner Name: ${RUNNER_NAME}"
echo ""

# Generate JIT config with unique label
RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runners/generate-jitconfig" \
    -d "{
        \"name\": \"${RUNNER_NAME}\",
        \"runner_group_id\": 1,
        \"labels\": [\"self-hosted\", \"${UNIQUE_LABEL}\"],
        \"work_folder\": \"_work\"
    }")

echo "API Response:"
echo "$RESPONSE" | jq .
echo ""

# Check for errors
if echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
    echo "❌ Error from GitHub API:"
    echo "$RESPONSE" | jq -r '.message'
    exit 1
fi

# Extract JIT config
JIT_CONFIG=$(echo "$RESPONSE" | jq -r '.encoded_jit_config')

if [ "$JIT_CONFIG" = "null" ] || [ -z "$JIT_CONFIG" ]; then
    echo "❌ Failed to get JIT config from API response"
    echo ""
    echo "Full API Response:"
    echo "$RESPONSE" | jq .
    echo ""
    echo "Possible issues:"
    echo "1. Token lacks 'administration:write' permission for repository"
    echo "2. GitHub App not installed on repository"
    echo "3. Endpoint URL incorrect"
    echo "4. Runner group ID invalid (trying with default group 1)"
    exit 1
fi

echo "✅ JIT Configuration generated successfully!"
echo ""
echo "Runner will ONLY pick jobs with label: ${UNIQUE_LABEL}"
echo ""
echo "Encoded JIT Config (first 100 chars):"
echo "${JIT_CONFIG:0:100}..."
echo ""

# Save to file with unique name
CONFIG_FILE="jit-config-${UNIQUE_LABEL}.txt"
echo "$JIT_CONFIG" > "$CONFIG_FILE"
echo "Saved to: $CONFIG_FILE"
echo ""

# Also save to default location for convenience
echo "$JIT_CONFIG" > jit-config.txt

# Decode and display (for verification)
echo "Decoded JIT Config (labels):"
echo "$JIT_CONFIG" | base64 -d 2>/dev/null | jq -r '.".runner"' | base64 -d 2>/dev/null | jq . || echo "(Could not decode)"
echo ""

echo "=========================================="
echo "Next step: Run the runner with this JIT config"
echo "Command: ./run-jit-runner.sh"
echo ""
echo "The runner will wait for jobs with label: ${UNIQUE_LABEL}"