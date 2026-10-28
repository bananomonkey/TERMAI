// navigation.dart — глобальный навигатор и наблюдатель экранов.
// Нужен ИИ-агенту: по имени экрана он понимает, куда перейти и что уже
// открыто, чтобы не плодить одинаковые страницы в стеке.
import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class ScreenObserver extends NavigatorObserver with ChangeNotifier {
  static final List<String> _stack = <String>[];

  static List<String> get stack => List.unmodifiable(_stack);
  static String get current => _stack.isEmpty ? '' : _stack.last;
  static bool has(String name) => _stack.contains(name);

  /// Только для тестов: сбросить историю между прогонами.
  static void reset() => _stack.clear();

  static String _name(Route<dynamic> route) =>
      route.settings.name ?? route.runtimeType.toString();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(_name(route));
    notifyListeners();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.isNotEmpty) _stack.removeLast();
    notifyListeners();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) return;
    if (_stack.isEmpty) {
      _stack.add(_name(newRoute));
    } else {
      _stack[_stack.length - 1] = _name(newRoute);
    }
    notifyListeners();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final i = _stack.lastIndexOf(_name(route));
    if (i >= 0) _stack.removeAt(i);
    notifyListeners();
  }
}

final screenObserver = ScreenObserver();
