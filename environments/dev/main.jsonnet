local p = (import '../../promtail/promtail.libsonnet');
local puj = (import '../../promtail/up-job.libsonnet');

local dexCfg = {
  tokenEndpoint: 'http://dex.dex.svc.cluster.local:5556/dex/token',
  username: 'admin@example.com',
  password: 'password',
  clientID: 'test',
  clientSecret: 'ZXhhbXBsZS1hcHAtc2VjcmV0',
};

local up = puj + puj.withResources {
  config+: {
    name: 'observatorium-up-logs',
    version: 'master-2020-09-28-120d857',
    image: 'quay.io/observatorium/up:' + self.version,
    commonLabels+:: {
      'app.kubernetes.io/instance': 'e2e-test',
    },
    backoffLimit: 5,
    resources: {
      limits: {
        memory: '128Mi',
        cpu: '500m',
      },
    },
    readEndpoint:: 'http://observatorium-xyz-observatorium-api.observatorium.svc.cluster.local:8080/api/logs/v1/test/api/v1/query',
    querySpec: {
      queries: [
        {
          name: 'obervatorium-test-tenant',
          query: '{observatorium="test"}',
        },
      ],
    },
  },
} + puj.withGetToken {
  config+: dexCfg {
    curlImage: 'docker.io/curlimages/curl',
  },
};

local promtail =
  p +
  p.withOpenShiftMixin {
    _config+:: dexCfg {
      namespace: 'observatorium',
      version: '1.6.1',
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
  };

promtail.manifests +
up.manifests
