import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

class ReceiveProfileDialog extends StatefulWidget {
  const ReceiveProfileDialog({super.key});

  @override
  State<ReceiveProfileDialog> createState() => _ReceiveProfileDialogState();
}

class _ReceiveProfileDialogState extends State<ReceiveProfileDialog> {
  HttpServer? _server;
  String? _qrData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _startServerAndGenerateQr();
  }

  Future<void> _startServerAndGenerateQr() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      const port = 8899;

      final router = shelf_router.Router();
      router.post('/add-profile', (shelf.Request request) async {
        final body = await request.readAsString();
        final json = jsonDecode(body);
        final url = json['url'] as String?;

        if (url != null && url.isNotEmpty) {
          print('Received subscription link: $url');
          if (mounted) Navigator.of(context).pop(url);
          return shelf.Response.ok('Link received by TV');
        }
        return shelf.Response.badRequest(body: 'URL not found');
      });

      _server = await shelf_io.serve(router.call, ip!, port);
      print('Server started at http://${_server?.address.host}:${_server?.port}');

      setState(() {
        _qrData = jsonEncode({
          'type': 'flclashx_tv_sync',
          'ip': _server?.address.host,
          'port': _server?.port,
        });
        _isLoading = false;
      });
    } catch (e) {
      print('Error starting server: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _server?.close(force: true);
    print('Server stopped');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(appLocalizations.receiveSubscriptionTitle),
      content: SizedBox(
        width: 300,
        height: 300,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _qrData != null
                ? Center(
                    child: QrImageView(
                      data: _qrData!,
                      version: QrVersions.auto,
                      size: 300.0,
                      backgroundColor: Colors.transparent,
                      dataModuleStyle: QrDataModuleStyle(
                        color: theme.colorScheme.onSurface,
                        dataModuleShape: QrDataModuleShape.square,
                      ),
                      eyeStyle: QrEyeStyle(
                        color: theme.colorScheme.onSurface,
                        eyeShape: QrEyeShape.square,
                      ),
                    ),
                  )
                : const Center(child: Text('Could not get IP address')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appLocalizations.cancel),
        ),
      ],
    );
  }
}