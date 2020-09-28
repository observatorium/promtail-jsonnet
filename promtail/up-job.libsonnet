local k = import 'ksonnet.beta.4/k.libsonnet';

{
  local up = self,

  config:: {
    name: error 'must provide name',
    version: error 'must provide version',
    image: error 'must provide image',
    backoffLimit: error 'must provide backoffLimit',
    readEndpoint: error 'must provide readEndpoint',

    querySpec: error 'must provide a query spec',

    commonLabels:: {
      'app.kubernetes.io/name': 'observatorium-up',
      'app.kubernetes.io/instance': up.config.name,
      'app.kubernetes.io/version': up.config.version,
      'app.kubernetes.io/component': 'test',
    },
  },

  configMap:
    local configmap = k.core.v1.configMap;
    configmap.new() +
    configmap.mixin.metadata.withName(up.config.name) +
    configmap.mixin.metadata.withLabels(up.config.commonLabels) +
    configmap.withData({
      'queries.yaml': std.manifestYamlDoc(up.config.querySpec),
    }),

  job:
    local job = k.batch.v1.job;
    local container = job.mixin.spec.template.spec.containersType;

    local c =
      container.new('observatorium-up', up.config.image) +
      container.withArgs(
        [
          '--endpoint-type=logs',
          '--endpoint-read=' + up.config.readEndpoint,
          '--queries-file=/var/up/queries.yaml',
          '--period=1s',
          '--duration=2m',
          '--initial-query-delay=5s',
          '--threshold=0.90',
        ]
      ) +
      container.withVolumeMounts([
        {
          name: up.config.name,
          mountPath: '/var/up',
          readOnly: false,
        },
      ]);

    job.new() +
    job.mixin.metadata.withName(up.config.name) +
    job.mixin.spec.withBackoffLimit(up.config.backoffLimit) +
    job.mixin.spec.template.metadata.withLabels(up.config.commonLabels) +
    job.mixin.spec.template.spec.withContainers([c]) {
      spec+: {
        template+: {
          spec+: {
            restartPolicy: 'OnFailure',
          },
        },
      },
    } + job.mixin.spec.template.spec.withVolumes([
      {
        configMap: {
          name: up.config.name,
        },
        name: up.config.name,
      },
    ]),

  withResources:: {
    local u = self,
    config+:: {
      resources: error 'must provide resources',
    },

    job+: {
      spec+: {
        template+: {
          spec+: {
            containers: [
              if c.name == 'observatorium-up' then c {
                resources: u.config.resources,
              } else c
              for c in super.containers
            ],
          },
        },
      },
    },
  },

  withGetToken:: {
    local job = k.batch.v1.job,
    local container = job.mixin.spec.template.spec.containersType,
    local u = self,
    config+:: {
      curl: error 'must provide image for cURL',
      tokenEndpoint: error 'must provide token endpoint',
      username: error 'must provide username',
      password: error 'must provide password',
      clientID: error 'must provide clientID',
      clientSecret: error 'must provide clientSecret',
    },

    job+: {
      spec+: {
        template+: {
          spec+: {
            local c =
              container.new('curl', u.config.curl) +
              container.withCommand([
                '/bin/sh',
                '-c',
                |||
                  curl --request POST \
                      --silent \
                      --url %s \
                      --header 'content-type: application/x-www-form-urlencoded' \
                      --data grant_type=password \
                      --data username=%s \
                      --data password=%s \
                      --data client_id=%s \
                      --data client_secret=%s \
                      --data scope="openid email" | sed 's/^{.*"id_token":[^"]*"\([^"]*\)".*}/\1/' > /var/shared/token
                ||| % [
                  u.config.tokenEndpoint,
                  u.config.username,
                  u.config.password,
                  u.config.clientID,
                  u.config.clientSecret,
                ],
              ]) +
              container.withVolumeMounts({
                name: 'shared',
                mountPath: '/var/shared',
                readOnly: false,
              }),

            initContainers+: [c],

            containers: [
              if c.name == 'observatorium-up' then c {
                resources: u.config.resources,
                args+: [
                  '--token-file=/var/shared/token',
                ],
              } + container.withVolumeMounts(
                c.volumeMounts + [
                  {
                    name: 'shared',
                    mountPath: '/var/shared',
                    readOnly: true,
                  },
                ]
              ) else c
              for c in super.containers
            ],
            volumes+: [
              {
                emptyDir: {},
                name: 'shared',
              },
            ],
          },
        },
      },
    },
  },

  manifests+:: {
    [up.config.name]: up.job,
    [up.config.name + '-configmap']: up.configMap,
  },
}
