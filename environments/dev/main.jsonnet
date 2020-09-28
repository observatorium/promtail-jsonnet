local p = (import '../../promtail/promtail.libsonnet');
local upJob = (import '../../promtail/up-job.libsonnet');

local defaultConfig = {
  images:: {
    curl: 'docker.io/curlimages/curl:7.72.0',
  },
  dex:: {
    tokenEndpoint: 'http://dex.dex.svc.cluster.local:5556/dex/token',
    username: 'admin@example.com',
    password: 'password',
    clientID: 'test',
    clientSecret: 'ZXhhbXBsZS1hcHAtc2VjcmV0',
  },
  obs:: {
    scheme: 'http',
    hostname: 'observatorium-xyz-observatorium-api.%s.svc.cluster.local' % self.namespace,
    port: 8080,
    namespace: 'observatorium',
    tenantId: 'test'
  },
  promtail:: {
    externalLabels: {
      observatorium: 'test',
    },
  },
};

local up =
  upJob +
  upJob.withResources +
  upJob.withGetToken {
    config+: defaultConfig.images + defaultConfig.dex {
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
      readEndpoint:: '%s://%s:%d/api/logs/v1/%s/api/v1/query' % [
        defaultConfig.obs.scheme,
        defaultConfig.obs.hostname,
        defaultConfig.obs.port,
        defaultConfig.obs.tenantId,
      ],
      querySpec: {
        queries: [
          {
            name: 'obervatorium-test-tenant',
            query: std.toString(defaultConfig.promtail.externalLabels),
          },
        ],
      },
    },
  };

local pt =
  p +
  p.withOpenShiftMixin {
    _images+:: defaultConfig.images,
    _config+:: defaultConfig.dex {
      namespace: defaultConfig.obs.namespace,
      version: '1.6.1',
      promtail_config+: {
        clients: [
          {
            local c = self,
            scheme:: defaultConfig.obs.scheme,
            hostname:: '%s:%d' % [
              defaultConfig.obs.hostname,
              defaultConfig.obs.port,
            ],
            tenant_id:: defaultConfig.obs.tenantId,
            external_labels: defaultConfig.promtail.externalLabels,
          },
        ],
      },
    },
  };

pt.manifests +
up.manifests
