// directions.dart — направления обучения. Каждое направление — отдельное
// пространство: свой маршрут, курсы, активный курс и статистика.
import 'models.dart';

class DirectionDef {
  final String id;
  final String category;
  final String title;
  final String shortTitle;
  final String desc;
  final List<String> courseIds;
  final String defaultCourseId;

  const DirectionDef({
    required this.id,
    required this.category,
    required this.title,
    required this.shortTitle,
    required this.desc,
    required this.courseIds,
    required this.defaultCourseId,
  });
}

const directionCategories = <String, String>{
  'languages': 'Языки',
  'programming': 'Программирование',
  'professions': 'Профессии',
  'custom': 'Мои направления',
};

/// Кастомные направления пользователя. Реестр мутируемый: при старте
/// store.dart наполняет его из config.customDirections, а create-диалог
/// добавляет новые.
final List<DirectionDef> customDirectionDefs = <DirectionDef>[];

String slugify(String title) {
  final t = title.trim().toLowerCase();
  final map = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  };
  final b = StringBuffer();
  for (final ch in t.codeUnits) {
    final c = String.fromCharCode(ch);
    if (map.containsKey(c)) {
      b.write(map[c]);
    } else if (RegExp(r'[a-z0-9]').hasMatch(c)) {
      b.write(c);
    } else {
      b.write('-');
    }
  }
  var r = b.toString().replaceAll(RegExp(r'-+'), '-');
  if (r.startsWith('-')) r = r.substring(1);
  if (r.endsWith('-')) r = r.substring(0, r.length - 1);
  return r.isEmpty ? 'custom' : r;
}

const directionCatalog = <DirectionDef>[
  DirectionDef(
    id: 'devops',
    category: 'professions',
    title: 'DevOps-инженер',
    shortTitle: 'DevOps',
    desc:
        'Linux → сети → Git → Docker → Kubernetes → CI/CD → Terraform → Ansible → мониторинг.',
    courseIds: [
      'linux',
      'networking',
      'git',
      'docker',
      'kubernetes',
      'cicd',
      'terraform',
      'ansible',
      'monitoring',
    ],
    defaultCourseId: 'linux',
  ),
  DirectionDef(
    id: 'english',
    category: 'languages',
    title: 'Английский',
    shortTitle: 'English',
    desc:
        'База A1: to be, Present Simple, артикли, вопросы и повседневная лексика.',
    courseIds: ['english-a1'],
    defaultCourseId: 'english-a1',
  ),
  DirectionDef(
    id: 'go',
    category: 'programming',
    title: 'Go',
    shortTitle: 'Go',
    desc: 'Синтаксис, типы, ошибки, тесты, горутины, каналы и HTTP-сервисы.',
    courseIds: ['go-basics'],
    defaultCourseId: 'go-basics',
  ),
];

DirectionDef? directionById(String id) {
  for (final d in directionCatalog) {
    if (d.id == id) return d;
  }
  for (final d in customDirectionDefs) {
    if (d.id == id) return d;
  }
  return null;
}

/// allDirectionDefs — каталог + кастомные, для валидации и выборщиков.
List<DirectionDef> get allDirectionDefs =>
    [...directionCatalog, ...customDirectionDefs];

String directionCategoryTitle(String category) =>
    directionCategories[category] ?? category;

/// directionForCourse — безопасное направление для старых или AI-курсов.
String directionForCourse(Course c) {
  if (c.direction.isNotEmpty) return c.direction;
  final t = (c.title + ' ' + c.desc).toLowerCase();
  if (t.contains('англ') || t.contains('english')) return 'english';
  if (t.contains('go ') || t.contains('golang')) return 'go';
  return 'devops';
}

String categoryForDirection(String direction) =>
    directionById(direction)?.category ?? 'professions';

List<DirectionDef> directionsForCategory(String category) =>
    allDirectionDefs.where((d) => d.category == category).toList();

class DirectionStats {
  final int courses;
  final int solved;
  final int total;
  final int xp;
  const DirectionStats({
    required this.courses,
    required this.solved,
    required this.total,
    required this.xp,
  });

  int get percent => total == 0 ? 0 : (solved / total * 100).round();
}
