import 'package:cached_network_image/cached_network_image.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/fade_box.dart';
import 'package:flclashx/widgets/pop_scope.dart';
import 'package:flclashx/widgets/search_order_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chip.dart';

class CommonScaffold extends ConsumerStatefulWidget {

  const CommonScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.sideNavigationBar,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.leading,
    this.title,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.appBarEditState,
    this.floatingActionButton,
    this.disableBackground = false,
  });

  CommonScaffold.open({
    Key? key,
    required Widget body,
    required String title,
    required Function onBack,
    required List<Widget> actions,
    bool disableBackground = false,
  }) : this(
          key: key,
          body: body,
          title: title,
          automaticallyImplyLeading: false,
          actions: actions,
          disableBackground: disableBackground,
          leading: IconButton(
            icon: const BackButtonIcon(),
            onPressed: () {
              onBack();
            },
          ),
        );
  final AppBar? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? sideNavigationBar;
  final Color? backgroundColor;
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  final AppBarEditState? appBarEditState;
  final FloatingActionButton? floatingActionButton;
  final bool disableBackground;

  @override
  ConsumerState<CommonScaffold> createState() => CommonScaffoldState();
}

class CommonScaffoldState extends ConsumerState<CommonScaffold> {
  late final ValueNotifier<AppBarState> _appBarState;
  final ValueNotifier<Widget?> _floatingActionButton = ValueNotifier(null);
  final ValueNotifier<List<String>> _keywordsNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _loading = ValueNotifier(false);

  final _textController = TextEditingController();

  Function(List<String>)? _onKeywordsUpdate;

  Widget? get _sideNavigationBar => widget.sideNavigationBar;

  set actions(List<Widget> actions) {
    _appBarState.value = _appBarState.value.copyWith(actions: actions);
  }

  bool get _isSearch => _appBarState.value.searchState?.isSearch == true;

  bool get _isEdit => _appBarState.value.editState?.isEdit == true;

  set onKeywordsUpdate(Function(List<String>)? onKeywordsUpdate) {
    _onKeywordsUpdate = onKeywordsUpdate;
  }

  @override
  void initState() {
    super.initState();
    _appBarState = ValueNotifier(
      AppBarState(
        editState: widget.appBarEditState,
      ),
    );
  }

  void updateSearchState(
    AppBarSearchState? Function(AppBarSearchState? state) builder,
  ) {
    _appBarState.value = _appBarState.value.copyWith(
      searchState: builder(
        _appBarState.value.searchState,
      ),
    );
  }

  void updateEditState(
    AppBarEditState? Function(AppBarEditState? state) builder,
  ) {
    _appBarState.value = _appBarState.value.copyWith(
      editState: builder(
        _appBarState.value.editState,
      ),
    );
  }

  set floatingActionButton(Widget? floatingActionButton) {
    if (_floatingActionButton.value != floatingActionButton) {
      _floatingActionButton.value = floatingActionButton;
    }
  }

  Widget _buildSearchingAppBarTheme(Widget child) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: colorScheme.brightness == Brightness.dark
              ? Colors.grey[900]
              : Colors.white,
          iconTheme: theme.primaryIconTheme.copyWith(color: Colors.grey),
          titleTextStyle: theme.textTheme.titleLarge,
          toolbarTextStyle: theme.textTheme.bodyMedium,
        ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: theme.inputDecorationTheme.hintStyle,
          border: InputBorder.none,
        ),
      ),
      child: child,
    );
  }

  Future<T?> loadingRun<T>(
    Future<T> Function() futureFunction, {
    String? title,
  }) async {
    _loading.value = true;
    try {
      final res = await futureFunction();
      _loading.value = false;
      return res;
    } catch (e) {
      globalState.showMessage(
        title: title ?? appLocalizations.tip,
        message: TextSpan(
          text: e.toString(),
        ),
      );
      _loading.value = false;
      return null;
    }
  }

  void _handleClearInput() {
    _textController.text = "";

    if (_appBarState.value.searchState != null) {
      _appBarState.value.searchState!.onSearch("");
    }
  }

  void _handleClear() {
    if (_textController.text.isNotEmpty) {
      _handleClearInput();
      return;
    }
    updateSearchState(
      (state) => state?.copyWith(
        isSearch: false,
      ),
    );
  }

  void _handleExitSearching() {
    _handleClearInput();
    updateSearchState(
      (state) => state?.copyWith(
        isSearch: false,
      ),
    );
  }

  @override
  void dispose() {
    _appBarState.dispose();
    _textController.dispose();
    _floatingActionButton.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CommonScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _appBarState.value = const AppBarState();
      _floatingActionButton.value = null;
      _textController.text = "";
      _keywordsNotifier.value = [];
      _onKeywordsUpdate = null;
    } else if (oldWidget.appBarEditState != widget.appBarEditState) {
      _appBarState.value = _appBarState.value.copyWith(
        editState: widget.appBarEditState,
      );
    }
  }

  void addKeyword(String keyword) {
    final isContains = _keywordsNotifier.value.contains(keyword);
    if (isContains) return;
    final keywords = List<String>.from(_keywordsNotifier.value)..add(keyword);
    _keywordsNotifier.value = keywords;
  }

  void _deleteKeyword(String keyword) {
    final isContains = _keywordsNotifier.value.contains(keyword);
    if (!isContains) return;
    final keywords = List<String>.from(_keywordsNotifier.value)
      ..remove(keyword);
    _keywordsNotifier.value = keywords;
  }

  Widget? _buildLeading() {
    if (_isEdit) {
      return IconButton(
        onPressed: _appBarState.value.editState?.onExit,
        icon: const Icon(Icons.close),
      );
    }
    return _isSearch
        ? IconButton(
            onPressed: _handleExitSearching,
            icon: const Icon(Icons.arrow_back),
          )
        : widget.leading;
  }

  Widget _buildTitle(AppBarSearchState? startState) => _isSearch
        ? TextField(
            autofocus: true,
            controller: _textController,
            style: context.textTheme.titleLarge,
            onChanged: (value) {
              if (startState != null) {
                startState.onSearch(value);
              }
            },
            decoration: InputDecoration(
              hintText: appLocalizations.search,
            ),
          )
        : Text(
            !_isEdit
                ? widget.title!
                : appLocalizations.selectedCountTitle(
                    "${_appBarState.value.editState?.editCount ?? 0}",
                  ),
          );

  List<Widget> _buildActions(
    AppBarSearchState? searchState,
    List<Widget> actions,
  ) {
    if (_isSearch) {
      return genActions([
        IconButton(
          onPressed: _handleClear,
          icon: const Icon(Icons.close),
        ),
      ]);
    }

    final hasSearch = searchState != null;
    final searchButton = IconButton(
      onPressed: () {
        updateSearchState(
          (state) => state?.copyWith(
            isSearch: true,
          ),
        );
      },
      icon: const Icon(Icons.search),
    );

    if (!hasSearch) {
      return genActions([
        ...actions,
      ]);
    }

    // For Proxies page we want search at the end; for others keep default
    // Check for explicit marker widget in actions to control search placement
    final shouldPutSearchAtEnd = actions.any((w) => w is SearchOrderMarker);

    if (shouldPutSearchAtEnd) {
      return genActions([
        ...actions,
        searchButton,
      ]);
    }

    return genActions([
      searchButton,
      ...actions,
    ]);
  
  }

  Widget _buildAppBarWrap(Widget child) {
    final appBar = _isSearch ? _buildSearchingAppBarTheme(child) : child;
    if (_isEdit || _isSearch) {
      return SystemBackBlock(
        child: CommonPopScope(
          onPop: () {
            if (_isEdit || _isSearch) {
              _handleExitSearching();
              _appBarState.value.editState?.onExit();
              return false;
            }
            return true;
          },
          child: appBar,
        ),
      );
    }
    return appBar;
  }

  PreferredSizeWidget _buildAppBar() {
    final backgroundUrl = widget.disableBackground ? null : ref.watch(backgroundUrlProvider);
    final isTransparent = backgroundUrl != null;
    
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Theme(
        data: Theme.of(context).copyWith(
          appBarTheme: AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  Theme.of(context).brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
              systemNavigationBarIconBrightness:
                  Theme.of(context).brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
              systemNavigationBarColor: widget.bottomNavigationBar != null
                  ? context.colorScheme.surfaceContainer
                  : context.colorScheme.surface,
              systemNavigationBarDividerColor: Colors.transparent,
            ),
          ),
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            widget.appBar ??
                ValueListenableBuilder<AppBarState>(
                  valueListenable: _appBarState,
                  builder: (_, state, __) => _buildAppBarWrap(
                      AppBar(
                        backgroundColor: isTransparent ? Colors.transparent : null,
                        elevation: isTransparent ? 0 : null,
                        centerTitle: widget.centerTitle ?? false,
                        automaticallyImplyLeading:
                            widget.automaticallyImplyLeading,
                        leading: _buildLeading(),
                        title: _buildTitle(state.searchState),
                        actions: _buildActions(
                          state.searchState,
                          state.actions.isNotEmpty
                              ? state.actions
                              : widget.actions ?? [],
                        ),
                      ),
                    ),
                ),
            ValueListenableBuilder(
              valueListenable: _loading,
              builder: (_, value, __) => value == true
                    ? const LinearProgressIndicator()
                    : Container(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(String? backgroundUrl) {
    if (backgroundUrl == null || backgroundUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: CachedNetworkImage(
        imageUrl: backgroundUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => const SizedBox.shrink(),
        errorWidget: (context, url, error) => const SizedBox.shrink(),
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) => Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                context.colorScheme.surface.withValues(alpha: 0.92),
                context.colorScheme.surface.withValues(alpha: 0.88),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    assert(widget.appBar != null || widget.title != null);
    final backgroundUrl = widget.disableBackground ? null : ref.watch(backgroundUrlProvider);
    
    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder(
            valueListenable: _keywordsNotifier,
            builder: (_, keywords, __) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_onKeywordsUpdate != null) {
                  _onKeywordsUpdate!(keywords);
                }
              });
              if (keywords.isEmpty) {
                return const SizedBox();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Wrap(
                  runSpacing: 8,
                  spacing: 8,
                  children: [
                    for (final keyword in keywords)
                      CommonChip(
                        label: keyword,
                        type: ChipType.delete,
                        onPressed: () {
                          _deleteKeyword(keyword);
                        },
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: widget.body,
          ),
        ],
      ),
    );
    
    final scaffold = Scaffold(
      appBar: _buildAppBar(),
      body: body,
      resizeToAvoidBottomInset: true,
      backgroundColor: backgroundUrl != null ? Colors.transparent : widget.backgroundColor,
      floatingActionButton: widget.floatingActionButton ??
          ValueListenableBuilder<Widget?>(
            valueListenable: _floatingActionButton,
            builder: (_, value, __) => IntrinsicWidth(
                child: IntrinsicHeight(
                  child: FadeScaleBox(
                    child: value ?? const SizedBox(),
                  ),
                ),
              ),
          ),
      bottomNavigationBar: widget.bottomNavigationBar,
    );
    
    final scaffoldWithBackground = backgroundUrl != null
        ? Stack(
            children: [
              _buildBackground(backgroundUrl),
              _buildOverlay(context),
              scaffold,
            ],
          )
        : scaffold;
    
    return _sideNavigationBar != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sideNavigationBar!,
              Expanded(
                flex: 1,
                child: scaffoldWithBackground,
              ),
            ],
          )
        : scaffoldWithBackground;
  }
}

List<Widget> genActions(List<Widget> actions, {double? space}) => <Widget>[
    ...actions.separated(
      SizedBox(
        width: space ?? 4,
      ),
    ),
    const SizedBox(
      width: 8,
    )
  ];
