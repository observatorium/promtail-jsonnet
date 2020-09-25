TMP_DIR := $(shell pwd)/tmp
BIN_DIR ?= $(TMP_DIR)/bin
GOBIN ?= $(BIN_DIR)

include .bingo/Variables.mk

SHELL=/usr/bin/env bash -o pipefail

default: environments/dev/manifests

vendor: $(JB)
	$(JB) install

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

JSONNET_SRC = $(shell find . -type f -not -path './*vendor/*' \( -name '*.libsonnet' -o -name '*.jsonnet' \))

.PHONY: fmt
fmt: $(JSONNETFMT) $(JSONNET_SRC)
	$(JSONNETFMT) -n 2 --max-blank-lines 2 --string-style s --comment-style s -i $(JSONNET_SRC)

environments/dev/manifests: environments/dev/main.jsonnet vendor $(JSONNET_SRC) $(JSONNET) $(GOJSONTOYAML)
	-make fmt
	-rm -rf environments/dev/manifests
	-mkdir -p environments/dev/manifests
	$(JSONNET) -J vendor -J lib -m environments/dev/manifests environments/dev/main.jsonnet  | xargs -I{} sh -c 'cat {} | $(GOJSONTOYAML) > {}.yaml' -- {}
	find environments/dev/manifests -type f ! -name '*.yaml' -delete

dev-deploy: environments/dev/manifests
	kubectl apply -n promtail -f environments/dev/manifests
