#!/bin/bash
# =============================================================================
# Flowker - Workflow Cost Benchmark Script
# =============================================================================
# This script measures resource consumption per workflow execution to estimate
# production costs. It captures metrics from all infrastructure components.
#
# Usage: ./scripts/benchmark_workflow_cost.sh [num_workflows]
# Default: 100 workflows (for quick test)
#
# Requirements:
# - Docker and Docker Compose
# - jq, bc, curl installed
# - Flowker stack running (or will be started)
# =============================================================================

set -e

# Configuration
NUM_WORKFLOWS=${1:-100}
FLOWKER_API="http://localhost:6681"
OIDC_MOCK="http://localhost:6721"
TEMPORAL_API="http://localhost:7233"
RESULTS_DIR="/tmp/flowker-benchmark-$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create results directory
mkdir -p "$RESULTS_DIR"
log_info "Results will be saved to: $RESULTS_DIR"

# =============================================================================
# Phase 1: Environment Check
# =============================================================================
log_info "Phase 1: Checking environment..."

check_dependencies() {
    local missing=()
    for cmd in docker jq bc curl; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
    log_success "All dependencies found"
}

check_docker_stack() {
    cd "$PROJECT_DIR"

    # Check if containers are running
    if ! docker compose ps --format json 2>/dev/null | jq -e '.' > /dev/null 2>&1; then
        log_warn "Docker stack not running. Starting..."
        docker compose up -d
        log_info "Waiting 90 seconds for services to initialize..."
        sleep 90
    else
        log_success "Docker stack is running"
    fi

    # Verify health
    local unhealthy=$(docker compose ps --format json | jq -r 'select(.Health != "healthy" and .Health != "" and .Health != null) | .Name' 2>/dev/null || echo "")
    if [ -n "$unhealthy" ]; then
        log_warn "Some services may not be fully healthy: $unhealthy"
        log_info "Waiting additional 30 seconds..."
        sleep 30
    fi
}

check_dependencies
check_docker_stack

# =============================================================================
# Phase 2: Baseline Metrics Collection
# =============================================================================
log_info "Phase 2: Collecting baseline metrics..."

collect_docker_stats() {
    local prefix=$1
    docker stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.NetIO}},{{.BlockIO}}" > "$RESULTS_DIR/${prefix}_docker_stats.csv"
}

collect_mongo_metrics() {
    local prefix=$1
    docker exec flowker-mongo mongosh -u admin -p flowker --authenticationDatabase admin --eval "JSON.stringify(db.serverStatus())" --quiet 2>/dev/null > "$RESULTS_DIR/${prefix}_mongo_status.json" || echo "{}" > "$RESULTS_DIR/${prefix}_mongo_status.json"
}

collect_postgres_metrics() {
    local prefix=$1
    docker exec flowker-postgres psql -U flowker -d flowker -t -c "SELECT json_build_object('connections', (SELECT count(*) FROM pg_stat_activity), 'transactions', (SELECT xact_commit + xact_rollback FROM pg_stat_database WHERE datname = 'flowker'), 'queries', (SELECT sum(calls) FROM pg_stat_statements));" 2>/dev/null > "$RESULTS_DIR/${prefix}_postgres_status.json" || echo "{}" > "$RESULTS_DIR/${prefix}_postgres_status.json"
}

collect_valkey_metrics() {
    local prefix=$1
    docker exec flowker-valkey valkey-cli -a flowker INFO stats 2>/dev/null > "$RESULTS_DIR/${prefix}_valkey_stats.txt" || echo "" > "$RESULTS_DIR/${prefix}_valkey_stats.txt"
}

collect_temporal_metrics() {
    local prefix=$1
    curl -s "$TEMPORAL_API/metrics" 2>/dev/null > "$RESULTS_DIR/${prefix}_temporal_metrics.txt" || echo "" > "$RESULTS_DIR/${prefix}_temporal_metrics.txt"
}

# Collect baseline
collect_docker_stats "baseline"
collect_mongo_metrics "baseline"
collect_postgres_metrics "baseline"
collect_valkey_metrics "baseline"
collect_temporal_metrics "baseline"

log_success "Baseline metrics collected"

# =============================================================================
# Phase 3: Get Authentication Token
# =============================================================================
log_info "Phase 3: Obtaining authentication token..."

get_auth_token() {
    local token=$(curl -s -X POST "$OIDC_MOCK/default/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials&client_id=test&client_secret=test&scope=openid" \
        2>/dev/null | jq -r '.access_token // empty')

    if [ -z "$token" ]; then
        log_warn "Could not get token from OIDC mock, trying without auth..."
        echo ""
    else
        echo "$token"
    fi
}

AUTH_TOKEN=$(get_auth_token)
if [ -n "$AUTH_TOKEN" ]; then
    log_success "Authentication token obtained"
    AUTH_HEADER="Authorization: Bearer $AUTH_TOKEN"
else
    log_warn "Running without authentication"
    AUTH_HEADER=""
fi

# =============================================================================
# Phase 4: Execute Workflows
# =============================================================================
log_info "Phase 4: Executing $NUM_WORKFLOWS workflows..."

# Check API health first
API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$FLOWKER_API/health" 2>/dev/null || echo "000")
if [ "$API_HEALTH" != "200" ]; then
    log_error "Flowker API not healthy (HTTP $API_HEALTH)"
    log_info "Attempting to check available endpoints..."
    curl -s "$FLOWKER_API/" 2>/dev/null | head -20 || true
    log_warn "Will attempt benchmark anyway..."
fi

# Prepare workflow payload
WORKFLOW_PAYLOAD='{
  "pipeline_id": "bench-PIPELINE_ID",
  "transaction_id": "bench-TX_ID",
  "tenant_id": "bench-tenant",
  "amount": "1500.00",
  "currency": "BRL",
  "user_id": "user-123",
  "user_type": "individual",
  "steps": [
    {"type": "KYC", "order": 1, "parameters": {}},
    {"type": "FRAUD", "order": 2, "parameters": {}},
    {"type": "AML", "order": 3, "parameters": {}}
  ]
}'

# Execute workflows and collect timing
EXEC_START=$(date +%s.%N)
SUCCESS_COUNT=0
FAILURE_COUNT=0
LATENCIES=()

for i in $(seq 1 $NUM_WORKFLOWS); do
    # Replace placeholders with unique IDs
    PAYLOAD=$(echo "$WORKFLOW_PAYLOAD" | sed "s/PIPELINE_ID/$i/g" | sed "s/TX_ID/$(uuidgen 2>/dev/null || echo $RANDOM)/g")

    # Execute workflow
    REQ_START=$(date +%s.%N)

    if [ -n "$AUTH_HEADER" ]; then
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$FLOWKER_API/api/v1/runtime/execute" \
            -H "$AUTH_HEADER" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" 2>/dev/null || echo -e "\n000")
    else
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$FLOWKER_API/api/v1/runtime/execute" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" 2>/dev/null || echo -e "\n000")
    fi

    REQ_END=$(date +%s.%N)
    LATENCY=$(echo "$REQ_END - $REQ_START" | bc)
    LATENCIES+=($LATENCY)

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
        ((SUCCESS_COUNT++))
    else
        ((FAILURE_COUNT++))
        if [ $FAILURE_COUNT -le 3 ]; then
            log_warn "Request $i failed with HTTP $HTTP_CODE"
            echo "$RESPONSE" | head -n -1 | head -5
        fi
    fi

    # Progress indicator
    if [ $((i % 10)) -eq 0 ]; then
        echo -ne "\r  Progress: $i/$NUM_WORKFLOWS (Success: $SUCCESS_COUNT, Failed: $FAILURE_COUNT)"
    fi
done

EXEC_END=$(date +%s.%N)
TOTAL_DURATION=$(echo "$EXEC_END - $EXEC_START" | bc)

echo ""
log_success "Workflow execution completed"

# =============================================================================
# Phase 5: Post-Test Metrics Collection
# =============================================================================
log_info "Phase 5: Collecting post-test metrics..."

# Wait for async processing
log_info "Waiting 10 seconds for async processing to complete..."
sleep 10

collect_docker_stats "final"
collect_mongo_metrics "final"
collect_postgres_metrics "final"
collect_valkey_metrics "final"
collect_temporal_metrics "final"

log_success "Final metrics collected"

# =============================================================================
# Phase 6: Calculate Results
# =============================================================================
log_info "Phase 6: Calculating results..."

# Calculate latency statistics
calc_stats() {
    local arr=("$@")
    local n=${#arr[@]}

    if [ $n -eq 0 ]; then
        echo "0,0,0,0"
        return
    fi

    # Sort array
    IFS=$'\n' sorted=($(sort -n <<<"${arr[*]}")); unset IFS

    # Min, Max
    local min=${sorted[0]}
    local max=${sorted[$((n-1))]}

    # Mean
    local sum=0
    for v in "${arr[@]}"; do
        sum=$(echo "$sum + $v" | bc)
    done
    local mean=$(echo "scale=4; $sum / $n" | bc)

    # P95
    local p95_idx=$(echo "scale=0; $n * 0.95 / 1" | bc)
    local p95=${sorted[$p95_idx]}

    echo "$min,$max,$mean,$p95"
}

LATENCY_STATS=$(calc_stats "${LATENCIES[@]}")
LATENCY_MIN=$(echo "$LATENCY_STATS" | cut -d',' -f1)
LATENCY_MAX=$(echo "$LATENCY_STATS" | cut -d',' -f2)
LATENCY_MEAN=$(echo "$LATENCY_STATS" | cut -d',' -f3)
LATENCY_P95=$(echo "$LATENCY_STATS" | cut -d',' -f4)

THROUGHPUT=$(echo "scale=2; $NUM_WORKFLOWS / $TOTAL_DURATION" | bc)

# Extract MongoDB ops delta
BASELINE_MONGO_OPS=$(cat "$RESULTS_DIR/baseline_mongo_status.json" | jq '.opcounters // {}' 2>/dev/null || echo "{}")
FINAL_MONGO_OPS=$(cat "$RESULTS_DIR/final_mongo_status.json" | jq '.opcounters // {}' 2>/dev/null || echo "{}")

MONGO_INSERT_DELTA=$(echo "$(echo "$FINAL_MONGO_OPS" | jq '.insert // 0') - $(echo "$BASELINE_MONGO_OPS" | jq '.insert // 0')" | bc 2>/dev/null || echo "0")
MONGO_QUERY_DELTA=$(echo "$(echo "$FINAL_MONGO_OPS" | jq '.query // 0') - $(echo "$BASELINE_MONGO_OPS" | jq '.query // 0')" | bc 2>/dev/null || echo "0")
MONGO_UPDATE_DELTA=$(echo "$(echo "$FINAL_MONGO_OPS" | jq '.update // 0') - $(echo "$BASELINE_MONGO_OPS" | jq '.update // 0')" | bc 2>/dev/null || echo "0")

MONGO_TOTAL_OPS=$(echo "$MONGO_INSERT_DELTA + $MONGO_QUERY_DELTA + $MONGO_UPDATE_DELTA" | bc 2>/dev/null || echo "0")
MONGO_OPS_PER_WORKFLOW=$(echo "scale=2; $MONGO_TOTAL_OPS / $SUCCESS_COUNT" | bc 2>/dev/null || echo "0")

# Extract Valkey ops delta
extract_valkey_stat() {
    local file=$1
    local stat=$2
    grep "^$stat:" "$file" 2>/dev/null | cut -d':' -f2 | tr -d ' ' || echo "0"
}

BASELINE_VALKEY_OPS=$(extract_valkey_stat "$RESULTS_DIR/baseline_valkey_stats.txt" "total_commands_processed")
FINAL_VALKEY_OPS=$(extract_valkey_stat "$RESULTS_DIR/final_valkey_stats.txt" "total_commands_processed")
VALKEY_OPS_DELTA=$(echo "$FINAL_VALKEY_OPS - $BASELINE_VALKEY_OPS" | bc 2>/dev/null || echo "0")
VALKEY_OPS_PER_WORKFLOW=$(echo "scale=2; $VALKEY_OPS_DELTA / $SUCCESS_COUNT" | bc 2>/dev/null || echo "0")

# =============================================================================
# Phase 7: Generate Report
# =============================================================================
log_info "Phase 7: Generating report..."

REPORT_FILE="$RESULTS_DIR/benchmark_report.json"

cat > "$REPORT_FILE" << EOF
{
  "benchmark_info": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "num_workflows_requested": $NUM_WORKFLOWS,
    "num_workflows_success": $SUCCESS_COUNT,
    "num_workflows_failed": $FAILURE_COUNT,
    "total_duration_seconds": $TOTAL_DURATION,
    "throughput_workflows_per_second": $THROUGHPUT
  },
  "latency_stats": {
    "min_seconds": $LATENCY_MIN,
    "max_seconds": $LATENCY_MAX,
    "mean_seconds": $LATENCY_MEAN,
    "p95_seconds": $LATENCY_P95
  },
  "resource_consumption": {
    "mongodb": {
      "total_ops_delta": $MONGO_TOTAL_OPS,
      "ops_per_workflow": $MONGO_OPS_PER_WORKFLOW,
      "breakdown": {
        "inserts": $MONGO_INSERT_DELTA,
        "queries": $MONGO_QUERY_DELTA,
        "updates": $MONGO_UPDATE_DELTA
      }
    },
    "valkey": {
      "total_ops_delta": $VALKEY_OPS_DELTA,
      "ops_per_workflow": $VALKEY_OPS_PER_WORKFLOW
    },
    "temporal": {
      "estimated_actions_per_workflow": 7,
      "note": "Based on code analysis: 1 workflow + 3 activities + 3 signals/queries"
    }
  },
  "cost_estimation": {
    "assumptions": {
      "temporal_cloud_per_action": 0.000025,
      "mongodb_atlas_m30_per_month": 389,
      "mongodb_ops_capacity_per_month": 2592000000,
      "valkey_elasticache_per_month": 94,
      "valkey_ops_capacity_per_month": 259200000000,
      "exchange_rate_usd_brl": 5.0
    },
    "per_workflow_usd": {
      "temporal": $(echo "scale=8; 7 * 0.000025" | bc),
      "mongodb": $(echo "scale=8; $MONGO_OPS_PER_WORKFLOW * 389 / 2592000000" | bc 2>/dev/null || echo "0"),
      "valkey": $(echo "scale=8; $VALKEY_OPS_PER_WORKFLOW * 94 / 259200000000" | bc 2>/dev/null || echo "0"),
      "total": $(echo "scale=8; (7 * 0.000025) + ($MONGO_OPS_PER_WORKFLOW * 389 / 2592000000) + ($VALKEY_OPS_PER_WORKFLOW * 94 / 259200000000)" | bc 2>/dev/null || echo "0.000175")
    },
    "per_workflow_brl": $(echo "scale=6; ((7 * 0.000025) + ($MONGO_OPS_PER_WORKFLOW * 389 / 2592000000) + ($VALKEY_OPS_PER_WORKFLOW * 94 / 259200000000)) * 5.0" | bc 2>/dev/null || echo "0.000875")
  },
  "files": {
    "baseline_docker_stats": "baseline_docker_stats.csv",
    "final_docker_stats": "final_docker_stats.csv",
    "baseline_mongo_status": "baseline_mongo_status.json",
    "final_mongo_status": "final_mongo_status.json",
    "baseline_valkey_stats": "baseline_valkey_stats.txt",
    "final_valkey_stats": "final_valkey_stats.txt"
  }
}
EOF

# =============================================================================
# Phase 8: Display Summary
# =============================================================================
echo ""
echo "========================================================================"
echo "                    FLOWKER BENCHMARK RESULTS"
echo "========================================================================"
echo ""
echo "EXECUTION SUMMARY"
echo "  Workflows requested:    $NUM_WORKFLOWS"
echo "  Workflows succeeded:    $SUCCESS_COUNT"
echo "  Workflows failed:       $FAILURE_COUNT"
echo "  Total duration:         ${TOTAL_DURATION}s"
echo "  Throughput:             ${THROUGHPUT} workflows/sec"
echo ""
echo "LATENCY (seconds)"
echo "  Min:                    ${LATENCY_MIN}s"
echo "  Max:                    ${LATENCY_MAX}s"
echo "  Mean:                   ${LATENCY_MEAN}s"
echo "  P95:                    ${LATENCY_P95}s"
echo ""
echo "RESOURCE CONSUMPTION (per workflow)"
echo "  MongoDB ops:            ~${MONGO_OPS_PER_WORKFLOW} ops"
echo "  Valkey ops:             ~${VALKEY_OPS_PER_WORKFLOW} ops"
echo "  Temporal actions:       ~7 actions (estimated)"
echo ""
echo "COST ESTIMATION (per workflow)"
COST_USD=$(echo "scale=6; (7 * 0.000025) + ($MONGO_OPS_PER_WORKFLOW * 389 / 2592000000) + ($VALKEY_OPS_PER_WORKFLOW * 94 / 259200000000)" | bc 2>/dev/null || echo "0.000175")
COST_BRL=$(echo "scale=4; $COST_USD * 5.0" | bc 2>/dev/null || echo "0.000875")
echo "  Estimated cost:         \$${COST_USD} USD"
echo "  Estimated cost:         R\$ ${COST_BRL} BRL"
echo ""
echo "RESULTS SAVED TO"
echo "  $RESULTS_DIR/"
echo ""
echo "========================================================================"

log_success "Benchmark completed!"

# Copy results summary to a known location
cp "$REPORT_FILE" "/tmp/flowker_benchmark_latest.json"
log_info "Latest results also available at: /tmp/flowker_benchmark_latest.json"
