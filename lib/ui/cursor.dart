import 'package:material_ui/material_ui.dart';

/// The hand over anything that can be clicked, on every platform. Material's
/// desktop default keeps the arrow over buttons, after the native toolkits.
const clickableCursor = WidgetStateMouseCursor.clickable;

const _buttonCursor = ButtonStyle(mouseCursor: clickableCursor);

ButtonStyle _withCursor(ButtonStyle? style) =>
    style?.merge(_buttonCursor) ?? _buttonCursor;

extension PointerCursorTheme on ThemeData {
  /// Every themed control shows [clickableCursor]; a control with no theme
  /// slot for its cursor, such as an InkWell, passes it itself.
  ThemeData get withPointerCursor => copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: _withCursor(filledButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _withCursor(textButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _withCursor(outlinedButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _withCursor(elevatedButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: _withCursor(iconButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: _withCursor(segmentedButtonTheme.style),
      selectedIcon: segmentedButtonTheme.selectedIcon,
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: _withCursor(menuButtonTheme.style),
    ),
    listTileTheme: listTileTheme.copyWith(mouseCursor: clickableCursor),
    switchTheme: switchTheme.copyWith(mouseCursor: clickableCursor),
    checkboxTheme: checkboxTheme.copyWith(mouseCursor: clickableCursor),
    radioTheme: radioTheme.copyWith(mouseCursor: clickableCursor),
    sliderTheme: sliderTheme.copyWith(mouseCursor: clickableCursor),
    tabBarTheme: tabBarTheme.copyWith(mouseCursor: clickableCursor),
    popupMenuTheme: popupMenuTheme.copyWith(mouseCursor: clickableCursor),
    floatingActionButtonTheme: floatingActionButtonTheme.copyWith(
      mouseCursor: clickableCursor,
    ),
    bottomNavigationBarTheme: bottomNavigationBarTheme.copyWith(
      mouseCursor: clickableCursor,
    ),
  );
}
