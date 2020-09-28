# promtail-jsonnet

[![Build Status](https://circleci.com/gh/observatorium/promtail-jsonnet.svg?style=svg)](https://circleci.com/gh/observatorium/promtail-jsonnet)

This repository contains configuration for deploying promtail for the Observatorium platform. It currently supports:

- [x] Plain promtail configuration (NS, RBAC, Daemonset) for any k8s cluster.
- [x] Specific configuration for running promtail an on OpenShift cluster, i.e. SCC and SecurityContext.
- [x] Fetching the oauth token from a third-party OAuth endpoint during promtail initialzation.
- [x] E2E testing based on [https://github.com/observatorium/deployments].
