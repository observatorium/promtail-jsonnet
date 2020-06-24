#!/usr/bin/env bash
set -x

kind create cluster

kubectl apply -f https://raw.githubusercontent.com/coreos/kube-prometheus/master/manifests/setup/prometheus-operator-0servicemonitorCustomResourceDefinition.yaml
kubectl apply -f https://raw.githubusercontent.com/coreos/kube-prometheus/master/manifests/setup/prometheus-operator-0prometheusruleCustomResourceDefinition.yaml
kubectl create ns dex || true
kubectl create ns observatorium-minio || true
kubectl create ns observatorium || true
kubectl apply -f ./vendor/observatorium/manifests


