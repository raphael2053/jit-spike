# Spike Plan: GitHub Actions Runner with Unique Label Assignment

## Objective
Validate that using **unique labels per job** can bind a runner to a specific job, proving it solves the "runner picks wrong job" problem.

## Key Discovery
JIT configuration API does NOT support `job_request_id` parameter. JIT creates ephemeral runners but still uses label-based matching. Therefore, we must use **unique labels** to guarantee job-to-runner assignment.

## Success Criteria
- ✅ Generate unique label for each job dispatch
- ✅ Create JIT runner with that unique label
- ✅ Dispatch workflow with unique label input
- ✅ Verify runner ONLY picks the job with matching unique label
- ✅ Confirm multiple runners can run jobs in parallel without conflicts
- ✅ Document the entire flow with evidence (logs, screenshots)

---

## Prerequisites

### 1. GitHub Setup
- **Repository**: Use existing test repository (or create `luxorlabs/jit-runner-spike`)
- **GitHub App or PAT**: 
  - Option A: GitHub App with `administration:write` permission on repository
  - Option B: Personal Access Token with `repo` and `admin:org` scopes
- **Test Workflows**: Create 2-3 simple workflow files to generate multiple queued jobs

### 2. Local Environment
- Docker installed (for runner container)
- `curl` or API client for GitHub API calls
- `jq` for JSON parsing
- GitHub CLI (`gh`) - optional but helpful

---

## Phase 1: Setup Test Environment (30 minutes)

### Step 1.1: Create Test Repository Structure
```bash
mkdir -p spike-jit-runner
cd spike-jit-runner

# Create test workflow files
mkdir -p .github/workflows
```

**File: `.github/workflows/test-unique-label.yml`**
```yaml
name: Test Unique Label Assignment
on:
  workflow_dispatch:
    inputs:
      unique_label:
        description: 'Unique runner label for this job'
        required: true
        type: string
      test_name:
        description: 'Test identifier'
        required: false
        type: string
        default: 'test'
    
jobs:
  build:
    runs-on: [self-hosted, ${{ inputs.unique_label }}]
    steps:
      - name: Identify Job
        run: |
          echo "=========================================="
          echo "Test Name: ${{ inputs.test_name }}"
          echo "Unique Label: ${{ inputs.unique_label }}"
          echo "Job ID: ${{ github.job }}"
          echo "Run ID: ${{ github.run_id }}"
          echo "Runner Name: ${{ runner.name }}"
          echo "Repository: ${{ github.repository }}"
          echo "=========================================="
          
      - name: Verify unique assignment
        run: |
          echo "This job should ONLY run on runner with label: ${{ inputs.unique_label }}"
          echo "If multiple jobs are queued, each should run on its assigned runner"
          
      - name: Simulate work
        run: |
          echo "Running for 30 seconds to allow observation..."
          sleep 30
          echo "Job complete!"
          
      - name: Report success
        run: |
          echo "=========================================="
          echo "✅ SUCCESS: Job executed on correct runner"
          echo "Label: ${{ inputs.unique_label }}"
          echo "Runner: ${{ runner.name }}"
          echo "=========================================="
```

### Step 1.2: Create GitHub App or Get PAT

**Option A: Create GitHub App (Recommended)**
```bash
# Navigate to: https://github.com/settings/apps/new
# Or for org: https://github.com/organizations/luxorlabs/settings/apps/new

App Name: JIT Runner Spike
Homepage URL: https://github.com/luxorlabs
Webhook: Uncheck "Active"

Permissions:
  Repository Permissions:
    - Actions: Read and write
    - Administration: Read and write
    - Metadata: Read-only

# After creation:
# 1. Generate private key (download .pem file)
# 2. Install app on test repository
# 3. Note App ID and Installation ID
```

**Option B: Create PAT**
```bash
# Navigate to: https://github.com/settings/tokens/new

Scopes:
  - repo (all)
  - admin:org > read:org
  - admin:org > manage_runners:org (if org-level)

# Copy token (starts with ghp_)
```

### Step 1.3: Prepare Docker Runner Image

**File: `Dockerfile`**
```dockerfile
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    git \
    sudo \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create runner user
RUN useradd -m -s /bin/bash runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Download GitHub Actions Runner (architecture-aware)
WORKDIR /home/runner
RUN RUNNER_VERSION="2.329.0" && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        RUNNER_ARCH="x64"; \
    elif [ "$ARCH" = "arm64" ]; then \
        RUNNER_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    echo "Downloading runner for architecture: $RUNNER_ARCH" && \
    curl -o actions-runner-linux.tar.gz -L \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" && \
    tar xzf actions-runner-linux.tar.gz && \
    rm actions-runner-linux.tar.gz && \
    chown -R runner:runner /home/runner

USER runner
WORKDIR /home/runner

# Default command (will be overridden)
CMD ["/bin/bash"]
```

**File: `build-runner-image.sh`**
```bash
#!/bin/bash
set -euo pipefail

echo "Building GitHub Actions Runner Docker image..."
docker build -t jit-runner-spike:latest .
echo "✅ Image built successfully!"
```

---

## Phase 2: Generate JIT Configuration (45 minutes)

### Step 2.1: Dispatch Jobs with Unique Labels

**File: `dispatch-job-with-label.sh`**
```bash
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
```

### Step 2.2: List Queued Jobs

**File: `list-queued-jobs.sh`**
```bash
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
```

### Step 2.3: Generate JIT Config with Unique Label

**File: `generate-jit-config.sh`**
```bash
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
```

---

## Phase 3: Run Runner with JIT Config (30 minutes)

### Step 3.1: Run Runner in Docker

**File: `run-jit-runner.sh`**
```bash
#!/bin/bash
set -euo pipefail

JIT_CONFIG_FILE="jit-config.txt"
UNIQUE_LABEL="${UNIQUE_LABEL:-unknown}"

if [ ! -f "$JIT_CONFIG_FILE" ]; then
    echo "Error: JIT config file not found: $JIT_CONFIG_FILE"
    echo "Run ./generate-jit-config.sh first"
    exit 1
fi

JIT_CONFIG=$(cat "$JIT_CONFIG_FILE")
CONTAINER_NAME="jit-runner-${UNIQUE_LABEL}"

echo "=========================================="
echo "Starting GitHub Actions Runner with JIT Config"
echo "Unique Label: ${UNIQUE_LABEL}"
echo "Container: ${CONTAINER_NAME}"
echo "=========================================="
echo ""

# Stop and remove any existing container with same name
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "Starting Docker container..."
docker run -it --rm \
    --name "$CONTAINER_NAME" \
    -e JIT_CONFIG="$JIT_CONFIG" \
    -e UNIQUE_LABEL="$UNIQUE_LABEL" \
    jit-runner-spike:latest \
    /bin/bash -c '
        set -euo pipefail
        
        echo "=========================================="
        echo "GitHub Actions Runner - JIT Mode"
        echo "Unique Label: ${UNIQUE_LABEL}"
        echo "=========================================="
        echo ""
        
        echo "JIT Config (first 100 chars):"
        echo "${JIT_CONFIG:0:100}..."
        echo ""
        
        # Install runner dependencies
        echo "Installing runner dependencies..."
        sudo ./bin/installdependencies.sh || true
        
        echo ""
        echo "Starting runner with JIT configuration..."
        echo "⏳ Runner will:"
        echo "   1. Decode JIT config and extract unique label"
        echo "   2. Connect to GitHub"
        echo "   3. Wait for job with label: ${UNIQUE_LABEL}"
        echo "   4. Execute ONLY that job"
        echo "   5. Exit and self-destruct"
        echo ""
        echo "This runner will IGNORE jobs without the unique label!"
        echo "=========================================="
        echo ""
        
        # Run with JIT config
        ./run.sh --jitconfig "$JIT_CONFIG" --once
        
        EXIT_CODE=$?
        
        echo ""
        echo "=========================================="
        echo "Runner finished with exit code: $EXIT_CODE"
        echo "Label: ${UNIQUE_LABEL}"
        echo "=========================================="
        
        exit $EXIT_CODE
    '

echo ""
echo "Container exited. Check logs above for results."
```

### Step 3.2: Monitor Job Execution

**File: `monitor-job.sh`**
```bash
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
```

---

## Phase 4: Validation & Testing (1 hour)

### Test Case 1: Single Job with Unique Label

**Expected Behavior:**
- Dispatch workflow with unique label (e.g., "tenki-1697543210-abc123")
- Create runner with same unique label via JIT config
- Runner claims ONLY the job with matching label
- Job executes successfully
- Runner exits and is removed from GitHub

**Validation Steps:**
```bash
# 1. Dispatch job with unique label
./dispatch-job-with-label.sh test-1
# Output: UNIQUE_LABEL="tenki-1697543210-abc123"

# 2. Export the unique label
export UNIQUE_LABEL="tenki-1697543210-abc123"

# 3. Generate JIT config with that label
./generate-jit-config.sh

# 4. Run runner (in separate terminal)
./run-jit-runner.sh

# 5. Monitor via GitHub UI or API
# Verify:
#  - Runner connects with label "tenki-1697543210-abc123"
#  - Job transitions: queued → in_progress → completed
#  - Runner auto-removes after job completion
```

### Test Case 2: Parallel Jobs with Unique Labels (Critical Test)

**Expected Behavior:**
- Dispatch 3 jobs with different unique labels
- Create 3 runners, each with their corresponding unique label
- Each runner picks ONLY its assigned job (no cross-contamination)
- All 3 jobs run in parallel
- All runners exit after their respective jobs complete

**Validation Steps:**
```bash
# Step 1: Dispatch 3 jobs with unique labels
echo "Dispatching 3 jobs with unique labels..."
./dispatch-job-with-label.sh test-1 > job1.log 2>&1 &
sleep 1
./dispatch-job-with-label.sh test-2 > job2.log 2>&1 &
sleep 1
./dispatch-job-with-label.sh test-3 > job3.log 2>&1 &
wait

# Extract unique labels from logs
LABEL1=$(grep "Unique Label:" job1.log | awk '{print $NF}')
LABEL2=$(grep "Unique Label:" job2.log | awk '{print $NF}')
LABEL3=$(grep "Unique Label:" job3.log | awk '{print $NF}')

echo "Labels: $LABEL1, $LABEL2, $LABEL3"

# Step 2: Wait for jobs to queue
sleep 5

# Step 3: Create 3 runners in parallel (separate terminals)

# Terminal 1:
export UNIQUE_LABEL="$LABEL1"
./generate-jit-config.sh && ./run-jit-runner.sh

# Terminal 2:
export UNIQUE_LABEL="$LABEL2"
./generate-jit-config.sh && ./run-jit-runner.sh

# Terminal 3:
export UNIQUE_LABEL="$LABEL3"
./generate-jit-config.sh && ./run-jit-runner.sh

# Verify:
#  ✅ Runner 1 picks only job with LABEL1
#  ✅ Runner 2 picks only job with LABEL2
#  ✅ Runner 3 picks only job with LABEL3
#  ✅ All 3 jobs complete successfully
#  ✅ No runner picks wrong job
```

### Test Case 3: Label Mismatch (Negative Test)

**Expected Behavior:**
- Dispatch job with label "tenki-aaa"
- Create runner with DIFFERENT label "tenki-bbb"
- Runner should NOT pick the job (label mismatch)
- Runner waits indefinitely or times out
- Job remains queued

**Validation Steps:**
```bash
# 1. Dispatch job with specific label
LABEL_JOB="tenki-test-aaa"
export UNIQUE_LABEL="$LABEL_JOB"
echo '{"ref":"main","inputs":{"unique_label":"'$LABEL_JOB'","test_name":"mismatch-test"}}' | \
  curl -s -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows/test-unique-label.yml/dispatches" \
    -d @-

# 2. Create runner with DIFFERENT label
LABEL_RUNNER="tenki-test-bbb"
export UNIQUE_LABEL="$LABEL_RUNNER"
./generate-jit-config.sh

# 3. Start runner
./run-jit-runner.sh

# Expected:
#  ❌ Runner does NOT pick job (label mismatch: aaa vs bbb)
#  ⏳ Runner waits for job with label "tenki-test-bbb"
#  ⏳ Job with label "tenki-test-aaa" remains queued
#  ✅ This proves label-based isolation works!
```

### Test Case 4: Race Condition (Stress Test)

**Expected Behavior:**
- Queue 10 jobs rapidly with unique labels
- Start 10 runners with matching labels
- Each runner picks exactly its assigned job
- No job stealing or cross-contamination

**Validation Steps:**
```bash
# Generate labels array
LABELS=()
for i in {1..10}; do
  LABELS+=("tenki-stress-$(date +%s%N)-$(openssl rand -hex 2)")
  sleep 0.1
done

# Dispatch 10 jobs
for i in {0..9}; do
  echo "Dispatching job $((i+1)) with label ${LABELS[$i]}"
  UNIQUE_LABEL="${LABELS[$i]}" ./dispatch-job-with-label.sh "stress-$((i+1))" &
done
wait

# Start 10 runners (in separate terminals or background)
for i in {0..9}; do
  (
    export UNIQUE_LABEL="${LABELS[$i]}"
    ./generate-jit-config.sh
    ./run-jit-runner.sh > "runner-$i.log" 2>&1
  ) &
done

# Monitor
watch -n 1 'gh run list --repo ${REPO_OWNER}/${REPO_NAME} --limit 10'

# Expected:
#  ✅ All 10 jobs complete successfully
#  ✅ Each job runs on correct runner (check logs)
#  ✅ No runner picks wrong job
#  ✅ No race conditions or deadlocks
```

---

## Phase 5: Documentation & Evidence (30 minutes)

### Step 5.1: Capture Evidence

**Create: `SPIKE_RESULTS.md`**
```markdown
# JIT Runner Spike Results

## Date
[DATE]

## Test Environment
- Repository: luxorlabs/jit-runner-spike
- Runner Version: 2.319.1
- Docker Image: jit-runner-spike:latest

## Test Cases

### Test 1: Single Job Execution
**Setup:**
- Queued 3 jobs (Job IDs: XXX, YYY, ZZZ)
- Generated JIT config for Job XXX

**Results:**
- ✅ Runner claimed only Job XXX
- ✅ Jobs YYY and ZZZ remained queued
- ✅ Job XXX completed successfully
- ✅ Runner exited after job completion

**Logs:**
```
[Paste runner logs here]
```

**Screenshots:**
- [Screenshot of queued jobs before runner start]
- [Screenshot of job in progress]
- [Screenshot of completed job with runner name]
- [Screenshot of other jobs still queued]

### Test 2: Parallel Execution
[Similar format]

### Test 3: Negative Test
[Similar format]

## Conclusion
[Summary of findings]

## Recommendations
[Next steps for production implementation]
```

### Step 5.2: Create Comparison Table

**Evidence to collect:**
- Runner logs showing job assignment
- GitHub UI screenshots showing job status
- API responses showing JIT config structure
- Timing data (how long to generate config, start runner, execute job)

---

## Phase 6: Cleanup (15 minutes)

### Step 6.1: Cleanup Script

**File: `cleanup.sh`**
```bash
#!/bin/bash
set -euo pipefail

echo "Cleaning up spike resources..."

# Stop Docker containers
docker rm -f jit-runner-test 2>/dev/null || true

# Clean up generated files
rm -f jit-config*.txt
rm -f spike-results-*.log

echo "✅ Cleanup complete!"
echo ""
echo "Note: Ephemeral runners created via JIT config are"
echo "automatically removed from GitHub after job completion."
echo "No manual cleanup needed in GitHub UI."
```

---

## Expected Outcomes

### Success Indicators
1. ✅ Unique labels generated successfully (timestamp + random)
2. ✅ JIT config created with unique label
3. ✅ Workflow dispatched with matching unique label
4. ✅ Runner connects to GitHub using JIT config
5. ✅ Runner claims ONLY the job with matching unique label
6. ✅ Job executes and completes successfully
7. ✅ Runner exits and is removed from GitHub automatically
8. ✅ Other queued jobs (with different labels) remain untouched
9. ✅ Multiple runners can run in parallel without conflicts
10. ✅ Label mismatch prevents runner from picking wrong job

### Failure Indicators
- ❌ Runner picks job with different label (label isolation broken)
- ❌ Multiple runners claim same job (race condition)
- ❌ Runner cannot connect with JIT config
- ❌ Job remains queued despite runner with matching label

---

## Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| Phase 1 | 30 min | Setup test repository, workflows, GitHub App |
| Phase 2 | 45 min | Queue jobs, generate JIT configs |
| Phase 3 | 30 min | Run runners with JIT config |
| Phase 4 | 60 min | Execute test cases and validate |
| Phase 5 | 30 min | Document results and capture evidence |
| Phase 6 | 15 min | Cleanup |
| **Total** | **3.5 hours** | End-to-end spike |

---

## Risks & Mitigations

### Risk 1: JIT Config API Not Available
- **Likelihood:** Low
- **Impact:** High
- **Mitigation:** Check GitHub docs first, verify API endpoint exists

### Risk 2: Docker Environment Differences
- **Likelihood:** Medium
- **Impact:** Low
- **Mitigation:** Use official Ubuntu base image, install dependencies properly

### Risk 3: GitHub Rate Limiting
- **Likelihood:** Low
- **Impact:** Medium
- **Mitigation:** Use GitHub App (higher rate limits than PAT)

---

## Next Steps After Spike

If spike is successful:
1. **Design production implementation:**
   - Add unique label generation to scheduler service
   - Generate label: `tenki-{job_id}-{timestamp}-{random}`
   - Create JIT config with unique label via GitHub API
   - Dispatch workflow with unique label as input
   - Update all workflow templates to accept `runner_label` input
   - Modify executor to pass JIT config to VMs
   - Update fc.sh cloud-init to use JIT config

2. **Workflow template changes:**
   ```yaml
   on:
     workflow_dispatch:
       inputs:
         runner_label:
           required: true
           type: string
   jobs:
     build:
       runs-on: ['self-hosted', '${{ inputs.unique_label }}']
   ```

3. **Scheduler logic:**
   ```go
   // Generate unique label
   runnerLabel := fmt.Sprintf("tenki-%s-%d-%s", 
     jobID, time.Now().Unix(), randomHex(4))
   
   // Create JIT config with label
   jitConfig := githubAPI.GenerateJITConfig(repo, runnerLabel)
   
   // Create VM with JIT config
   vm := nodeAgent.CreateVM(jitConfig)
   
   // Dispatch workflow with label
   githubAPI.DispatchWorkflow(repo, workflow, map[string]string{
     "runner_label": runnerLabel,
   })
   ```

4. **Testing strategy:**
   - Unit tests for unique label generation (collision resistance)
   - Integration tests for scheduler → nodeagent → VM flow
   - E2E tests with parallel job execution
   - Load tests (50+ concurrent jobs)

5. **Rollout plan:**
   - Feature flag: `use_unique_labels` (default: false)
   - Gradual rollout: 10% → 50% → 100%
   - Monitor: Job assignment accuracy, completion rates
   - Fallback: Registration token if JIT generation fails

If spike fails:
1. Document failure reasons (label isolation not working?)
2. Explore alternative solutions:
   - Pre-created runner pool with unique labels
   - Custom runner with job ID claiming
   - Serialize job execution (no parallelism)
   - Use GitHub Hosted runners (not self-hosted)

---

## Questions to Answer

1. ✅ Can we generate JIT config for a specific job?
2. ✅ Does JIT config actually bind runner to specific job?
3. ✅ What happens if job is already claimed/completed?
4. ✅ How long does JIT config remain valid?
5. ✅ Can we use same JIT config for multiple runners? (Should be NO)
6. ✅ Does runner auto-cleanup after job completion?

---

## References

- [GitHub API: Generate JIT Config](https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#create-configuration-for-a-just-in-time-runner-for-a-repository)
- [GitHub Actions Runner Releases](https://github.com/actions/runner/releases)
- [Actions Runner Controller (JIT usage)](https://github.com/actions/actions-runner-controller)
