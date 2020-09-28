local config = (import 'promtail/config.libsonnet');
local scrape_config = (import 'promtail/scrape_config.libsonnet');
local kausal = (import 'ksonnet-util/kausal.libsonnet');

config + scrape_config {
  _images+:: {
    curl: error 'Provide curl image to access oauth token',
    promtail: 'grafana/promtail:%s' % $._config.version,
  },

  _config+:: {
    namespace: error 'Provide a namespace for promtail deployment',
    tokenEndpoint: error 'Provide bearer token endpoint',
    username: error 'Provide username for token point authentication',
    password: error 'Provide password for token point authentication',
    clientID: error 'Provide client id for token point authentication',
    clientSecret: error 'Provide client secret for token point authentication',
    promtail_config+: {
      clients: error 'Provide promtail client configurations',
      container_root_path: '/var/lib/docker',
    },

    promtail_cluster_role_name: 'observatorium-promtail',
    promtail_configmap_name: 'observatorium-promtail',
    promtail_pod_name: 'observatorium-promtail',

    commonLabels:: {
      'app.kubernetes.io/name': 'observatorium-promtail',
      'app.kubernetes.io/component': 'promtail',
      'app.kubernetes.io/instance': 'observatorium',
      'app.kubernetes.io/version': $._config.version,
      'app.kubernetes.io/part-of': 'observatorium',
    },
  },

  local k = kausal {
    _config+:: {
      namespace: $._config.namespace,
    },
  },

  promtailNamespace::
    k.core.v1.namespace.new($._config.namespace),

  promtailServiceAccount::
    k.core.v1.serviceAccount.new($._config.promtail_cluster_role_name) {
      metadata+: {
        namespace: $._config.namespace,
      },
    },

  defaultPolicyRules:
    local policyRule = k.rbac.v1beta1.policyRule;
    [
      policyRule.new() +
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['nodes', 'nodes/proxy', 'services', 'endpoints', 'pods']) +
      policyRule.withVerbs(['get', 'list', 'watch']),
    ],

  promtailClusterRole::
    local clusterRole = k.rbac.v1.clusterRole;
    clusterRole.new() +
    clusterRole.mixin.metadata.withName($._config.promtail_cluster_role_name) +
    clusterRole.withRules($.defaultPolicyRules),

  promtailClusterRoleBinding::
    local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
    local subject = k.rbac.v1beta1.subject;
    clusterRoleBinding.new() +
    clusterRoleBinding.mixin.metadata.withName($._config.promtail_cluster_role_name) +
    clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
    clusterRoleBinding.mixin.roleRef.withKind('ClusterRole') +
    clusterRoleBinding.mixin.roleRef.withName($._config.promtail_cluster_role_name) +
    clusterRoleBinding.withSubjects([
      subject.new() +
      subject.withKind('ServiceAccount') +
      subject.withName($._config.promtail_cluster_role_name) +
      subject.withNamespace($._config.namespace),
    ]),

  promtail_config+:: {
    local client_config(client) = client {
      url: '%(scheme)s://%(hostname)s/api/logs/v1/%(tenant_id)s/api/v1/push' % client,
      bearer_token_file: '/var/shared/token',
    },

    clients: std.map(client_config, $._config.promtail_config.clients),
  },

  promtailConfigMap::
    local configMap = k.core.v1.configMap;
    configMap.new($._config.promtail_configmap_name) +
    configMap.mixin.metadata.withNamespace($._config.namespace) +
    configMap.mixin.metadata.withLabels($._config.commonLabels) +
    configMap.withData({
      'promtail.yml': std.manifestYamlDoc($.promtail_config),
    }),

  local container = k.core.v1.container,
  local volumeMount = {
    name: 'shared',
    mountPath: '/var/shared',
    readOnly: false,
  },

  promtailContainer::
    container.new('promtail', $._images.promtail) +
    container.withPorts(k.core.v1.containerPort.new(name='http-metrics', port=80)) +
    container.withArgsMixin(k.util.mapToFlags({
      'config.file': '/etc/promtail/promtail.yml',
    })) +
    container.withEnv([
      container.envType.fromFieldPath('HOSTNAME', 'spec.nodeName'),
    ]) +
    container.mixin.readinessProbe.httpGet.withPath('/ready') +
    container.mixin.readinessProbe.httpGet.withPort(80) +
    container.mixin.readinessProbe.withInitialDelaySeconds(10) +
    container.mixin.readinessProbe.withTimeoutSeconds(1) +
    container.withVolumeMounts(volumeMount),

  promtailInitContainer::
    container.new('promtail-init', $._images.curl) +
    container.withVolumeMounts(volumeMount) +
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
        $._config.tokenEndpoint,
        $._config.username,
        $._config.password,
        $._config.clientID,
        $._config.clientSecret,
      ],
    ]),


  promtailDaemonSet::
    local daemonSet = k.apps.v1.daemonSet;
    daemonSet.new($._config.promtail_pod_name, [$.promtailContainer]) +
    daemonSet.mixin.metadata.withNamespace($._config.namespace) +
    daemonSet.mixin.metadata.withLabels($._config.commonLabels) +
    daemonSet.mixin.spec.template.metadata.withLabels($._config.commonLabels) +
    daemonSet.mixin.spec.selector.withMatchLabels($._config.commonLabels) +
    daemonSet.mixin.spec.template.spec.withInitContainers($.promtailInitContainer) +
    daemonSet.mixin.spec.template.spec.withServiceAccount($._config.promtail_cluster_role_name) +
    daemonSet.mixin.spec.template.spec.withVolumes({ emptyDir: {}, name: 'shared' }) +
    k.util.configVolumeMount(
      $._config.promtail_configmap_name,
      '/etc/promtail'
    ) +
    k.util.hostVolumeMount(
      'varlog',
      '/var/log',
      '/var/log'
    ) +
    k.util.hostVolumeMount(
      'varlibdockercontainers',
      $._config.promtail_config.container_root_path + '/containers',
      $._config.promtail_config.container_root_path + '/containers',
      readOnly=true
    ),

  withOpenShiftMixin:: {
    local cfg = self,

    promtailDaemonSet+:: {
      spec+: {
        template+: {
          spec+: {
            containers: [
              c {
                securityContext: {
                  privileged: true,
                },
              }
              for c in super.containers
              if c.name == cfg.promtailContainer.name
            ],
          },
        },
      },
    },

    promtailClusterRole+::
      local clusterRole = k.rbac.v1.clusterRole;
      local policyRule = k.rbac.v1beta1.policyRule;
      clusterRole.new() +
      clusterRole.mixin.metadata.withName($._config.promtail_cluster_role_name) +
      clusterRole.withRules(cfg.defaultPolicyRules + [
        policyRule.new() +
        policyRule.withApiGroups(['security.openshift.io']) +
        policyRule.withResources(['securitycontextconstraints']) +
        policyRule.withVerbs(['use']) {
          resourceNames: ['hostmount-anyuid', 'privileged'],
        },
      ]),
  },

  manifests:: {
    'observatorium-namespace': $.promtailNamespace,
    'observatorium-promtail-serviceaccount': $.promtailServiceAccount,
    'observatorium-promtail-clusterrole': $.promtailClusterRole,
    'observatorium-promtail-clusterrolebinding': $.promtailClusterRoleBinding,
    'observatorium-promtail-configmap': $.promtailConfigMap,
    'observatorium-promtail-daemonset': $.promtailDaemonSet,
  },
}
