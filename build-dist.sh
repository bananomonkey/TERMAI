#!/usr/bin/env bash
# Собирает самодостаточную папку dist/TERMAI: Go-бинарник + whisper-cli + модель.
# Приложение ищет whisper-cli и ggml-*.bin рядом с собой, поэтому комплект переносим целиком.
set -e
cd "$(dirname "$0")"

APP=dist/TERMAI
WHISPER_SRC="${WHISPER_SRC:-$HOME/whisper.cpp}"
MODEL_SRC="${MODEL_SRC:-$HOME/.config/termai/ggml-base.bin}"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"

mkdir -p "$APP"

echo "→ собираю termai…"
go build -ldflags "-s -w" -o "$APP/termai" .
[ -f icon.png ] && cp -f icon.png "$APP/" || true

echo "→ кладу whisper-cli…"
if [ -x "$WHISPER_SRC/build/bin/whisper-cli" ]; then
    cp -f "$WHISPER_SRC/build/bin/whisper-cli" "$APP/whisper-cli"
elif command -v whisper-cli >/dev/null 2>&1; then
    cp -f "$(command -v whisper-cli)" "$APP/whisper-cli"
else
    echo "ОШИБКА: whisper-cli не найден."
    echo "Собери whisper.cpp:"
    echo "  git clone https://github.com/ggml-org/whisper.cpp ~/whisper.cpp"
    echo "  cd ~/whisper.cpp && cmake -B build && cmake --build build -j"
    echo "и повтори, либо задай WHISPER_SRC=/путь/к/whisper.cpp"
    exit 1
fi
chmod +x "$APP/whisper-cli"

echo "→ кладу модель…"
if [ -f "$MODEL_SRC" ]; then
    cp -f "$MODEL_SRC" "$APP/ggml-base.bin"
elif [ -f "$APP/ggml-base.bin" ]; then
    echo "   модель уже на месте"
else
    echo "   качаю ggml-base.bin (~148 МБ)…"
    curl -L --fail -o "$APP/ggml-base.bin.part" "$MODEL_URL"
    mv "$APP/ggml-base.bin.part" "$APP/ggml-base.bin"
fi

echo
echo "Готово: $APP"
ls -lh "$APP"
echo
echo "Запуск: ./$APP/termai"
