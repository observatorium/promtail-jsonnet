

dev-manifests:
	-rm -rf environments/dev/manifests
	-mkdir -p environments/dev/manifests
	jsonnet -J vendor -J lib -m environments/dev/manifests environments/dev/main.jsonnet

dev-deploy: dev-manifests
	kubectl apply -n promtail -f environments/dev/manifests
