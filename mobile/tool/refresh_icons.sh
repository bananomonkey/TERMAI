#!/usr/bin/env bash
# Пересобирает иконку приложения: PNG → mipmap/adaptive/splash.
# Запускать из mobile/:  bash tool/refresh_icons.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 tool/make_icon.py

python3 - <<'PY'
from PIL import Image
img = Image.open('assets/icon/termai_fg.png').convert('RGBA').resize((512, 512), Image.LANCZOS)
img.save('android/app/src/main/res/drawable-nodpi/splash_logo.png')
print('splash_logo.png updated')
PY

dart run flutter_launcher_icons

# flutter_launcher_icons добавляет inset 16% — из-за него вокруг зелёного
# экрана появлялся тёмный ободок. Убираем inset: экран заполняет маску.
python3 - <<'PY'
from pathlib import Path
p = Path('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
p.write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <!-- Без inset: зелёный экран заполняет маску лаунчера, без тёмного ободка -->
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
''', encoding='utf-8')
print('adaptive icon inset removed')
PY
