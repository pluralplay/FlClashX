import 'dart:async';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'item.dart';

class ConnectionsView extends ConsumerStatefulWidget {
  const ConnectionsView({super.key});

  @override
  ConsumerState<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends ConsumerState<ConnectionsView>
    with PageMixin {
  final _connectionsStateNotifier = ValueNotifier<ConnectionsState>(
    const ConnectionsState(),
  );
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  Timer? timer;

  @override
  List<Widget> get actions => [
        IconButton(
          onPressed: () async {
            clashCore.closeConnections();
            _connectionsStateNotifier.value =
                _connectionsStateNotifier.value.copyWith(
              connections: await clashCore.getConnections(),
            );
          },
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ];

  @override
  Null Function(String value) get onSearch => (value) {
        _connectionsStateNotifier.value =
            _connectionsStateNotifier.value.copyWith(
          query: value,
        );
      };

  @override
  Null Function(List<String> keywords) get onKeywordsUpdate => (keywords) {
        _connectionsStateNotifier.value =
            _connectionsStateNotifier.value.copyWith(keywords: keywords);
      };

  Future<void> _updateConnections() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        _connectionsStateNotifier.value =
            _connectionsStateNotifier.value.copyWith(
          connections: await clashCore.getConnections(),
        );
        timer = Timer(const Duration(seconds: 1), () async {
          _updateConnections();
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      isCurrentPageProvider(
        PageLabel.connections,
        handler: (pageLabel, viewMode) =>
            pageLabel == PageLabel.tools && viewMode == ViewMode.mobile,
      ),
      (prev, next) {
        if (prev != next && next == true) {
          initPageState();
        }
      },
      fireImmediately: true,
    );
    _updateConnections();
  }

  Future<void> _handleBlockConnection(String id) async {
    clashCore.closeConnection(id);
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      connections: await clashCore.getConnections(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    _connectionsStateNotifier.dispose();
    _scrollController.dispose();
    timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ConnectionsState>(
      valueListenable: _connectionsStateNotifier,
      builder: (_, state, __) {
        final connections = state.list;
        if (connections.isEmpty) {
          return NullStatus(
            label: appLocalizations.nullTip(appLocalizations.connections),
          );
        }
        return CommonScrollBar(
          controller: _scrollController,
          child: ListView.separated(
            controller: _scrollController,
            itemBuilder: (_, index) {
              final connection = connections[index];
              return ConnectionItem(
                key: Key(connection.id),
                connection: connection,
                onClickKeyword: (value) {
                  context.commonScaffoldState?.addKeyword(value);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.block),
                  onPressed: () {
                    _handleBlockConnection(connection.id);
                  },
                ),
              );
            },
            separatorBuilder: (context, index) => const Divider(
                height: 0,
              ),
            itemCount: connections.length,
          ),
        );
      },
    );
}
