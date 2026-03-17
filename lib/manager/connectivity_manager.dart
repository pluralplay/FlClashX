import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityManager extends StatefulWidget {

  const ConnectivityManager({
    super.key,
    this.onConnectivityChanged,
    required this.child,
  });
  final Function(List<ConnectivityResult> results)? onConnectivityChanged;
  final Widget child;

  @override
  State<ConnectivityManager> createState() => _ConnectivityManagerState();
}

class _ConnectivityManagerState extends State<ConnectivityManager> {
  late StreamSubscription subscription;

  @override
  void initState() {
    super.initState();
    subscription = Connectivity().onConnectivityChanged.listen((results) async {
      if (widget.onConnectivityChanged != null) {
        widget.onConnectivityChanged!(results);
      }
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
