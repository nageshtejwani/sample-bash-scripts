#!/bin/bash

# List all Helm releases
helm list -o json | jq -r '.[] | {name: .name, namespace: .namespace, chart: .chart, app_version: .app_version, status: .status}'

FLAG_LABEL="auto-cleanup"  # Replace with your desired label key

function get_flagged_namespaces() {
    kubectl get namespaces -l "${FLAG_LABEL}=true" -o json |\
        jq -r '.items[] | {name: .metadata.name, creationTimestamp: .metadata.creationTimestamp, retentionDays: .metadata.labels.retentionDays}'
}

function should_delete_namespace() {
    creation_timestamp=$1
    retention_days=$2

    # Calculate expiration time
    expiration_time=$(date -d "${creation_timestamp} +${retention_days} days" +%s)
    current_time=$(date +%s)

    # Return true if current time is past expiration time
    [[ $current_time -gt $expiration_time ]]
}

function delete_namespace() {
    namespace=$1
    echo "Force deleting namespace: $namespace"

    kubectl patch namespace "$namespace" \
        -p '{"metadata":{"finalizers":[]}}' --type=merge

    if [[ $? -eq 0 ]]; then
        echo "Namespace $namespace successfully deleted."
    else
        echo "Failed to delete namespace $namespace."
    fi
}

function cleanup_flagged_namespaces() {
    while true; do
        flagged_namespaces=$(get_flagged_namespaces)

        if [[ -z $flagged_namespaces ]]; then
            echo "No flagged namespaces found. Exiting."
            break
        fi

        echo "$flagged_namespaces" | while read -r ns_info; do
            namespace_name=$(echo "$ns_info" | jq -r '.name')
            creation_timestamp=$(echo "$ns_info" | jq -r '.creationTimestamp')
            retention_days=$(echo "$ns_info" | jq -r '.retentionDays')

            if should_delete_namespace "$creation_timestamp" "$retention_days"; then
                delete_namespace "$namespace_name"
            else
                echo "Namespace $namespace_name is still within retention period."
            fi
        done

        echo "Waiting for namespaces to clean up..."
        sleep 10
    done
}

cleanup_flagged_namespaces
