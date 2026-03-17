import 'dart:async';
import 'dart:math';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/widgets/fade_box.dart';
import 'package:flutter/material.dart';

class MessageManager extends StatefulWidget {

  const MessageManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  State<MessageManager> createState() => MessageManagerState();
}

class MessageManagerState extends State<MessageManager> {
  final _messagesNotifier = ValueNotifier<List<CommonMessage>>([]);
  final List<CommonMessage> _bufferMessages = [];
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _messagesNotifier.dispose();
    super.dispose();
  }

  Future<void> message(String text) async {
    final commonMessage = CommonMessage(
      id: utils.uuidV4,
      text: text,
    );
    commonPrint.log(text);
    _bufferMessages.add(commonMessage);
    await _showMessage();
  }

  Future<void> _showMessage() async {
    if (_pushing == true) {
      return;
    }
    _pushing = true;
    while (_bufferMessages.isNotEmpty) {
      final commonMessage = _bufferMessages.removeAt(0);
      _messagesNotifier.value = List.from(_messagesNotifier.value)
        ..add(
          commonMessage,
        );
      await Future.delayed(const Duration(seconds: 1));
      Future.delayed(commonMessage.duration, () {
        _handleRemove(commonMessage);
      });
      if (_bufferMessages.isEmpty) {
        _pushing = false;
      }
    }
  }

  Future<void> _handleRemove(CommonMessage commonMessage) async {
    _messagesNotifier.value = List<CommonMessage>.from(_messagesNotifier.value)
      ..remove(commonMessage);
  }

  @override
  Widget build(BuildContext context) => Stack(
      children: [
        widget.child,
        ValueListenableBuilder(
          valueListenable: _messagesNotifier,
          builder: (_, messages, __) => FadeThroughBox(
              margin: const EdgeInsets.only(
                top: kToolbarHeight + 8,
                left: 12,
                right: 12,
              ),
              alignment: Alignment.topRight,
              child: messages.isEmpty
                  ? const SizedBox()
                  : LayoutBuilder(
                      key: Key(messages.last.id),
                      builder: (_, constraints) => Card(
                          shape: const RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(12.0),
                            ),
                          ),
                          elevation: 10,
                          color: context.colorScheme.surfaceContainerHigh,
                          child: Container(
                            width: min(
                              constraints.maxWidth,
                              500,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                            child: Text(
                              messages.last.text,
                            ),
                          ),
                        ),
                    ),
            ),
        ),
      ],
    );
}
