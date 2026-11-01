// update_banner.dart — ненавязчивый баннер новой версии на главной.
// Не устанавливает APK молча: открывает страницу релиза/скачивания.
import 'package:flutter/material.dart';

import '../main.dart';
import 'design_system.dart';
import 'theme.dart';

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final info = controller.availableUpdate;
        if (info == null ||
            !info.available ||
            info.latest == controller.config.ignoredUpdate) {
          return const SizedBox.shrink();
        }
        final note = info.notes.trim().replaceAll(RegExp(r'\s+'), ' ');
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: appCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            accent: C.accent.withAlpha(105),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.system_update_alt, size: 20, color: C.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Доступна версия ${info.latest}',
                          style: AppText.title.copyWith(fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(
                        note.isEmpty
                            ? 'Скачай APK и установи поверх текущей версии.'
                            : note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: C.muted),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () async {
                          final ok = await controller.openAvailableUpdate();
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Не удалось открыть страницу загрузки')),
                            );
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.download_outlined, size: 17),
                        label: const Text('Скачать обновление',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Скрыть это обновление',
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => controller.dismissAvailableUpdate(),
                  icon: Icon(Icons.close, size: 17, color: C.muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
