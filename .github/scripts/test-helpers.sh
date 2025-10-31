#!/bin/bash
# Test helper functions for GitHub Actions scripts
# Usage: source .github/scripts/test-helpers.sh

# Mock GitHub Actions environment variables
export GITHUB_OUTPUT=$(mktemp)
export GITHUB_ENV=$(mktemp)

# Cleanup function
cleanup_test() {
    rm -f "$GITHUB_OUTPUT" "$GITHUB_ENV"
}

# Helper to read GitHub Actions outputs
get_output() {
    local key=$1
    grep "^${key}=" "$GITHUB_OUTPUT" | cut -d'=' -f2-
}

# Mock spot-instance-advisor command (for testing find-cheapest-instance.sh)
mock_spot_instance_advisor() {
    cat << EOF
{
  "spot_prices": [
    {
      "instance_type": "ecs.c8y.2xlarge",
      "zone": "cn-hangzhou-j",
      "price_per_core": 0.1
    },
    {
      "instance_type": "ecs.c8y.4xlarge",
      "zone": "cn-hangzhou-k",
      "price_per_core": 0.095
    },
    {
      "instance_type": "ecs.c8y.xlarge",
      "zone": "cn-hangzhou-b",
      "price_per_core": 0.12
    }
  ]
}
EOF
}

# Mock aliyun CLI command (for testing create/wait/cleanup scripts)
mock_aliyun() {
    local command=$1
    shift
    
    case "$command" in
        "ecs RunInstances")
            echo '{"InstanceIdSets":{"InstanceIdSet":["i-test123456"]}}'
            ;;
        "ecs DescribeInstances")
            local instance_id=$1
            if [[ "$instance_id" == *"test123456"* ]]; then
                echo '{"Instances":{"Instance":[{"Status":"Running"}]}}'
            else
                echo '{"Instances":{"Instance":[{"Status":"Starting"}]}}'
            fi
            ;;
        "ecs DeleteInstance")
            echo '{"RequestId":"test-request-id"}'
            ;;
        *)
            echo "{}"
            ;;
    esac
}

