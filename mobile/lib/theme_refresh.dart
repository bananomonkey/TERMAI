// theme_refresh.dart — сигнал «палитра изменилась».
// pageRoute слушает его и пересоздаёт страницу с новым ключом, не сбрасывая
// стек навигации. Так ИИ может переключить тему прямо из чата.
import 'package:flutter/foundation.dart';

final ValueNotifier<int> themeRevision = ValueNotifier<int>(0);

/// Страницы с этим маркером не пересоздаются при смене темы: они сами
/// слушают controller и перекрашиваются без потери состояния.
abstract class PreserveOnTheme {}
