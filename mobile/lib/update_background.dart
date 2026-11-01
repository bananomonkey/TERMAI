// update_background.dart — периодическая проверка GitHub в WorkManager.
// Уведомление показывается только один раз на версию и только если
// пользователь не выключил обновления/уведомления.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'models.dart';
import 'notifications.dart';
import 'update_service.dart';

const updateTaskName = 'termai-update-check';

@pragma('vm:entry-point')
void updateCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != updateTaskName) return true;
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final raw = await UpdateService.backgroundConfig();
      final cfg = Config.fromJson(raw);
      if (!cfg.updatesAutoCheck ||
          !cfg.notificationsEnabled ||
          !cfg.updatesNotifications) {
        return true;
      }
      final info = await UpdateService.check();
      if (!info.available || info.latest.isEmpty) return true;
      if (cfg.lastNotifiedUpdate == info.latest) return true;
      if (!await UpdateService.shouldNotify(info.latest)) return true;
      final shown =
          await notificationService.showUpdate(info.latest, info.notes);
      if (shown) await UpdateService.markNotified(info.latest);
    } catch (_) {
      // Сеть может быть недоступна — WorkManager повторит позже.
    }
    return true;
  });
}

Future<void> initUpdateWorker() async {
  if (!Platform.isAndroid) return;
  try {
    await Workmanager().initialize(updateCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      updateTaskName,
      updateTaskName,
      frequency: const Duration(hours: 12),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (_) {
    // без WorkManager ручная и foreground-проверка всё равно работают
  }
}

Future<void> cancelUpdateWorker() async {
  if (!Platform.isAndroid) return;
  try {
    await Workmanager().cancelByUniqueName(updateTaskName);
  } catch (_) {}
}
