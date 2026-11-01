// generation_operation.dart — состояние длительных ИИ-операций TERMAI.
//
// Одна операция не блокирует остальные возможности приложения, но не даёт
// запустить вторую генерацию поверх первой. Этапы и счётчики отражают только
// реально выполненные шаги: проценты здесь не выдумываются.

enum GenerationKind { task, courses, fill, continuation }

class GenerationCanceled implements Exception {
  const GenerationCanceled();

  @override
  String toString() => 'Операция отменена.';
}

class GenerationOperation {
  final GenerationKind kind;
  final String title;
  final DateTime startedAt = DateTime.now();
  final Stopwatch elapsed = Stopwatch()..start();

  String stage = 'Подготовка';
  String detail = '';
  int current = 0;
  int total = 0;
  bool cancelRequested = false;
  bool finished = false;
  String error = '';

  GenerationOperation(this.kind, this.title);

  bool get active => !finished;
  bool get canCancel => active && !finished;

  /// update — фиксирует реальный этап. current/total задаются только тогда,
  /// когда известен фактический объём работы (например, число курсов).
  void update(String nextStage,
      {String? nextDetail, int? current, int? total}) {
    if (finished) return;
    stage = nextStage;
    if (nextDetail != null) detail = nextDetail;
    if (current != null) this.current = current;
    if (total != null) this.total = total;
  }

  void advance([String? nextDetail]) {
    if (finished) return;
    current++;
    if (nextDetail != null) detail = nextDetail;
  }

  void requestCancel() {
    if (finished) return;
    cancelRequested = true;
    stage = 'Отмена';
    detail = 'Останавливаю после текущего шага…';
  }

  void throwIfCanceled() {
    if (cancelRequested) throw const GenerationCanceled();
  }

  void finish({String? error}) {
    finished = true;
    elapsed.stop();
    if (error != null && error.isNotEmpty) this.error = error;
    if (cancelRequested) {
      stage = 'Отменено';
      detail = 'Операция отменена.';
    } else if (this.error.isNotEmpty) {
      stage = 'Ошибка';
      detail = this.error;
    } else {
      stage = 'Готово';
      detail = 'Операция завершена.';
    }
  }
}

class GenerationOperations {
  final Map<GenerationKind, GenerationOperation> _byKind = {};

  GenerationOperation? get active {
    for (final op in _byKind.values) {
      if (op.active) return op;
    }
    return null;
  }

  bool get isBusy => active != null;

  bool isActive(GenerationKind kind) => _byKind[kind]?.active ?? false;

  GenerationOperation? of(GenerationKind kind) => _byKind[kind];

  /// begin — атомарно занимает слот. Вторая генерация получает понятную
  /// ошибку, а не пустой ответ и не «зависший» интерфейс.
  GenerationOperation begin(GenerationKind kind, String title) {
    final running = active;
    if (running != null) {
      throw StateError(
          'Уже выполняется «${running.title}». Дождись завершения или отмени операцию.');
    }
    final op = GenerationOperation(kind, title);
    _byKind[kind] = op;
    return op;
  }

  void clearFinished() {
    _byKind.removeWhere((_, op) => !op.active);
  }
}
