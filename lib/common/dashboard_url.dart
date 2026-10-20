const _anyHosts = {'', '0.0.0.0', '::', '[::]'};

String zashboardUrl(String controller, {String secret = ''}) {
  final address = controller.trim();
  final colon = address.lastIndexOf(':');
  var host = colon < 0 ? address : address.substring(0, colon);
  final port = colon < 0 ? '' : address.substring(colon + 1);
  if (_anyHosts.contains(host)) {
    host = '127.0.0.1';
  }
  final hostname = host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
  final query = {
    'hostname': hostname,
    if (port.isNotEmpty) 'port': port,
    if (secret.isNotEmpty) 'secret': secret,
  };
  final params = [
    for (final entry in query.entries)
      '${entry.key}=${Uri.encodeQueryComponent(entry.value)}',
  ].join('&');
  final origin = port.isEmpty ? host : '$host:$port';
  return 'http://$origin/ui/#/setup?$params';
}
