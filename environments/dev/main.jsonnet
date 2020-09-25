local p = (import '../../promtail/promtail.libsonnet');

p {
  _config+:: {
    namespace: 'observatorium',
    version: 'v1.6.0',
  },
}
