#!/usr/bin/env bash

set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/artifacts}"
KIND_CLUSTER_NAME="observatorium-promtail"
KUBECTL="${KUBECTL:-./tmp/bin/kubectl}"
OS_TYPE=$(echo `uname -s` | tr '[:upper:]' '[:lower:]')

trap 'tear_down; exit 0' EXIT

setup() {
    source .bingo/variables.env
    $KIND create cluster --name "${KIND_CLUSTER_NAME}"
    curl -L https://storage.googleapis.com/kubernetes-release/release/"$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"/bin/$OS_TYPE/amd64/kubectl -o ./tmp/bin/kubectl
    chmod +x ./tmp/bin/kubectl
}

test_e2e(){
    $KUBECTL apply -f https://raw.githubusercontent.com/coreos/kube-prometheus/master/manifests/setup/prometheus-operator-0servicemonitorCustomResourceDefinition.yaml
    $KUBECTL apply -f https://raw.githubusercontent.com/coreos/kube-prometheus/master/manifests/setup/prometheus-operator-0prometheusruleCustomResourceDefinition.yaml
    $KUBECTL create ns dex || true
    $KUBECTL create ns observatorium-minio || true
    $KUBECTL create ns observatorium || true
    $KUBECTL apply -f ./vendor/observatorium/manifests

    $KUBECTL rollout status --timeout=10m -n observatorium-minio deploy/minio || (must_gather "$ARTIFACT_DIR" && exit 1)
    $KUBECTL rollout status --timeout=10m -n observatorium deploy/observatorium-xyz-loki-distributor || (must_gather "$ARTIFACT_DIR" && exit 1)
    $KUBECTL rollout status --timeout=10m -n observatorium statefulset/observatorium-xyz-loki-ingester || (must_gather "$ARTIFACT_DIR" && exit 1)
    $KUBECTL rollout status --timeout=10m -n observatorium statefulset/observatorium-xyz-loki-querier || (must_gather "$ARTIFACT_DIR" && exit 1)

    $KUBECTL apply -f environments/dev/manifests

    $KUBECTL rollout status --timeout=10m -n observatorium daemonset/observatorium-promtail || (must_gather "$ARTIFACT_DIR" && exit 1)
}

tear_down(){
    source .bingo/variables.env
    $KIND delete cluster --name "${KIND_CLUSTER_NAME}"
}

must_gather() {
    local artifact_dir="$1"

    for namespace in default dex observatorium observatorium-minio; do
        mkdir -p "$artifact_dir/$namespace"

        for name in $($KUBECTL get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}') ; do
            $KUBECTL -n "$namespace" describe pod "$name" > "$artifact_dir/$namespace/$name.describe"
            $KUBECTL -n "$namespace" get pod "$name" -o yaml > "$artifact_dir/$namespace/$name.yaml"

            for initContainer in $($KUBECTL -n "$namespace" get po "$name" -o jsonpath='{.spec.initContainers[*].name}') ; do
                $KUBECTL -n "$namespace" logs "$name" -c "$initContainer" > "$artifact_dir/$namespace/$name-$initContainer.logs"
            done

            for container in $($KUBECTL -n "$namespace" get po "$name" -o jsonpath='{.spec.containers[*].name}') ; do
                $KUBECTL -n "$namespace" logs "$name" -c "$container" > "$artifact_dir/$namespace/$name-$container.logs"
            done
        done
    done

    $KUBECTL describe nodes > "$artifact_dir/nodes"
    $KUBECTL get pods --all-namespaces > "$artifact_dir/pods"
    $KUBECTL get daemonset --all-namespaces > "$artifact_dir/daemonsets"
    $KUBECTL get deploy --all-namespaces > "$artifact_dir/deployments"
    $KUBECTL get statefulset --all-namespaces > "$artifact_dir/statefulsets"
    $KUBECTL get services --all-namespaces > "$artifact_dir/services"
    $KUBECTL get endpoints --all-namespaces > "$artifact_dir/endpoints"
}

main(){
    setup
    test_e2e
}

main
