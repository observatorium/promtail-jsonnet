local scrape_config = import 'promtail/scrape_config.libsonnet';
local config = import 'promtail/config.libsonnet';
local k = (import 'ksonnet-util/kausal.libsonnet') + {
    _config+:: {
        namespace: 'promtail',
    }
};

local pt = config + scrape_config {
    _config+:: {
        namespace: 'promtail',
        promtail_config+: {
            clients: [
                {
                    scheme:: 'http',
                    // this isn't going to work because we need to go to the API
                    hostname:: 'observatorium-xyz-loki-distributor-http.observatorium.svc.cluster.local:3100',
                    external_labels: {},
                }
            ],
            container_root_path: '/var/lib/docker',
        },
    },

    '01-namespace.json':
        k.core.v1.namespace.new($._config.namespace),

    local policyRule = k.rbac.v1beta1.policyRule,
    rbac::
        k.util.rbac($._config.promtail_cluster_role_name, [
            policyRule.new() +
            policyRule.withApiGroups(['']) +
            policyRule.withResources(['nodes', 'nodes/proxy', 'services', 'endpoints', 'pods']) +
            policyRule.withVerbs(['get', 'list', 'watch']),
        ]),

    promtail_config+:: {
        local service_url(client) =
            if std.objectHasAll(client, 'username') then
                '%(scheme)s://%(username)s:%(password)s@%(hostname)s/loki/api/v1/push' % client
            else
                '%(scheme)s://%(hostname)s/loki/api/v1/push' % client,

        local client_config(client) = client {
            url: service_url(client),
        },

        clients: std.map(client_config, $._config.promtail_config.clients),
    },

    local configMap = k.core.v1.configMap,

    '10-promtail_config_map.json':
        configMap.new($._config.promtail_configmap_name) +
        configMap.withData({
            'promtail.yml': k.util.manifestYaml($.promtail_config),
        }),

    promtail_args:: {
        'config.file': '/etc/promtail/promtail.yml',
    },

    local container = k.core.v1.container,

    promtail_container::
        container.new('promtail', $._images.promtail) +
        container.withPorts(k.core.v1.containerPort.new(name='http-metrics', port=80)) +
        container.withArgsMixin(k.util.mapToFlags($.promtail_args)) +
        container.withEnv([
            container.envType.fromFieldPath('HOSTNAME', 'spec.nodeName'),
        ]) +
        container.mixin.readinessProbe.httpGet.withPath('/ready') +
        container.mixin.readinessProbe.httpGet.withPort(80) +
        container.mixin.readinessProbe.withInitialDelaySeconds(10) +
        container.mixin.readinessProbe.withTimeoutSeconds(1),

    local daemonSet = k.apps.v1.daemonSet,

    '20-promtail_daemonset.json':
        daemonSet.new($._config.promtail_pod_name, [$.promtail_container]) +
        daemonSet.mixin.spec.template.spec.withServiceAccount($._config.promtail_cluster_role_name) +
        k.util.configVolumeMount($._config.promtail_configmap_name, '/etc/promtail') +
        k.util.hostVolumeMount('varlog', '/var/log', '/var/log') +
        k.util.hostVolumeMount('varlibdockercontainers', $._config.promtail_config.container_root_path + '/containers', $._config.promtail_config.container_root_path + '/containers', readOnly=true),
};

// rbac creates sub-documents so we need to flatten them
pt + {
    ['15-rbac_' + f + '.json']: pt.rbac[f]
    for f in std.objectFields(pt.rbac)
}
