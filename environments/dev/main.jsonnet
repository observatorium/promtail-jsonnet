local p = (import '../../promtail/promtail.libsonnet');

(
  p +
  p.withOpenShiftMixin {
    _config+:: {
      namespace: 'observatorium',
      version: '1.6.1',
      tokenEndpoint: 'http://dex.dex.svc.cluster.local:5556/dex/token',
      username: 'admin@example.com',
      password: 'password',
      clientID: 'test',
      clientSecret: 'ZXhhbXBsZS1hcHAtc2VjcmV0',
      promtail_config+: {
        clients: [
          {
            local c = self,
            scheme:: 'http',
            hostname:: 'observatorium-xyz-observatorium-api.observatorium.svc.cluster.local:8080',
            tenant_id:: 'test',
            external_labels: {
              observatorium: 'test',
            },
          },
        ],
      },
    },
  }
).manifests
