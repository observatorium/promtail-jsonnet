local p = (import '../../promtail/promtail.libsonnet');

p {
  _config+:: {
    namespace: 'observatorium',
  },
}
