// tasks.go — модель курса/задачи/песочницы, встроенные курсы с теорией
// в markdown (примеры команд) и мини-тестами по теории.
package main

import (
    "crypto/sha1"
    "encoding/hex"
)

const (
    taskCmd  = "cmd"
    taskQuiz = "quiz"
)

// ---------- модель ----------

type HistEntry struct {
    Cmd string `json:"cmd"`
    Out string `json:"out"`
}

type QuizQ struct {
    Question string   `json:"question"`
    Options  []string `json:"options"`
    Correct  int      `json:"correct"`
}

type ImageInfo struct {
    ID         string   `json:"id"`
    Repo       string   `json:"repo"`
    Tag        string   `json:"tag"`
    SizeMB     int      `json:"size_mb"`
    Env        []string `json:"env,omitempty"`
    Entrypoint string   `json:"entrypoint,omitempty"`
    Cmd        string   `json:"cmd,omitempty"`
    Layers     []string `json:"layers,omitempty"`
}

type ContainerInfo struct {
    ID         string   `json:"id"`
    Name       string   `json:"name"`
    Image      string   `json:"image"`
    Status     string   `json:"status"`
    Ports      string   `json:"ports,omitempty"`
    Mounts     []string `json:"mounts,omitempty"`
    Networks   []string `json:"networks,omitempty"`
    Execs      []string `json:"execs,omitempty"`
    LogsViewed bool     `json:"logs_viewed,omitempty"`
}

type SandboxState struct {
    Workdir    string                    `json:"workdir"`
    Files      map[string]string         `json:"files"`
    Images     map[string]*ImageInfo     `json:"images"`
    Containers map[string]*ContainerInfo `json:"containers"`
    Volumes    map[string]string         `json:"volumes"`
    Networks   []string                  `json:"networks"`
    Events     []string                  `json:"events,omitempty"`
}

type Task struct {
    ID         string       `json:"id"`
    Title      string       `json:"title"`
    Kind       string       `json:"kind"`
    Difficulty int          `json:"difficulty"`
    Theory     []string     `json:"theory"`
    Quiz       []QuizQ      `json:"quiz,omitempty"`
    Goal       string       `json:"goal"`
    Hints      []string     `json:"hints"`
    Check      string       `json:"check"`
    Expected   string       `json:"expected_output,omitempty"`
    Solution   string       `json:"solution,omitempty"`
    Peeked     bool         `json:"peeked,omitempty"`
    Start      SandboxState `json:"start_state"`
}

type Course struct {
    ID       string   `json:"id"`
    Title    string   `json:"title"`
    Desc     string   `json:"desc,omitempty"`
    Tasks    []Task   `json:"tasks,omitempty"`
    Syllabus []string `json:"syllabus"`
}

// ---------- помощники ----------

func baseState() SandboxState {
    return SandboxState{
        Workdir:    "/workspace",
        Files:      map[string]string{},
        Images:     map[string]*ImageInfo{},
        Containers: map[string]*ContainerInfo{},
        Volumes:    map[string]string{},
        Networks:   []string{"bridge", "host", "none"},
    }
}

func fakeID(seed string) string {
    h := sha1.Sum([]byte(seed))
    return hex.EncodeToString(h[:6])
}

func pulled(repo, tag string, sizeMB int) *ImageInfo {
    return &ImageInfo{ID: "sha256:" + fakeID(repo+":"+tag), Repo: repo, Tag: tag, SizeMB: sizeMB}
}

func running(name, image, ports string) *ContainerInfo {
    return &ContainerInfo{ID: fakeID("container:" + name), Name: name, Image: image, Status: "running", Ports: ports}
}

// ---------- встроенные курсы ----------

func builtinCourses() []Course {
    tasks := builtinTasks()
    diffs := map[string]int{
        "hello-world": 1, "run-nginx": 2, "exec": 2, "logs": 2, "build-basics": 2,
        "copy-order": 3, "env": 2, "volumes": 3, "networks": 3, "multi-stage": 4,
        "compose": 3, "depends-on": 4, "optimize": 4, "entrypoint-cmd": 3, "debug-broken": 4,
    }
    for i := range tasks {
        tasks[i].Kind = taskCmd
        tasks[i].Difficulty = diffs[tasks[i].ID]
    }

    return []Course{
        {
            ID:    "docker",
            Title: "Docker",
            Desc:  "От hello-world до compose, оптимизации и отладки. После встроенных задач ИИ продолжает по программе.",
            Tasks: tasks,
            Syllabus: []string{
                "cmd: .dockerignore и чистый контекст сборки",
                "cmd: ARG — аргументы сборки",
                "cmd: HEALTHCHECK в Dockerfile",
                "cmd: restart policy: no, on-failure, always",
                "cmd: лимиты ресурсов --memory --cpus",
                "cmd: docker cp — файлы между хостом и контейнером",
                "cmd: теги, дайджесты и push в registry",
                "cmd: docker save/load — перенос образа файлом",
                "cmd: docker system prune — чистка диска",
                "cmd: compose: volumes, env_file и переменные",
                "quiz: контейнер против виртуалки — изоляция и накладные расходы",
                "quiz: слои образа и кэш сборки — почему это работает быстро",
            },
        },
        {
            ID:    "linux",
            Title: "Linux",
            Desc:  "Командная строка, файлы, права, процессы, сеть, скрипты — база для всего остального.",
            Syllabus: []string{
                "cmd: файловая система: ls, cd, pwd, типы файлов",
                "cmd: работа с файлами: cat, less, head, tail, touch, cp, mv, rm",
                "quiz: права доступа rwx и числа 755/644",
                "cmd: chmod, chown на практике",
                "cmd: пользователи: whoami, id, sudo, /etc/passwd",
                "cmd: процессы: ps aux, top, kill и сигналы",
                "quiz: SIGTERM против SIGKILL — в чём разница",
                "cmd: systemd: systemctl status/start/enable",
                "cmd: пакеты: apt update/install/remove",
                "cmd: поиск: grep -r, find по имени и содержимому",
                "cmd: пайпы и перенаправления | > >> 2>",
                "quiz: stdin, stdout, stderr и файловые дескрипторы",
                "cmd: текст: sed-замены, sort | uniq -c, awk-основы",
                "cmd: сеть: ip a, ping, curl, ss -tulpn",
                "quiz: порты и модель клиент-сервер в TCP/IP",
                "cmd: ssh: ключи, ssh-copy-id, ~/.ssh/config",
                "cmd: архивы tar/gzip, скачивание wget/curl",
                "cmd: cron: crontab -e и расписание",
                "cmd: переменные окружения: env, export, .bashrc",
                "quiz: PATH — как оболочка находит программы",
                "cmd: bash-скрипты: shebang, переменные, if, for",
                "cmd: диски: df -h, du -sh, точки монтирования",
                "quiz: что такое swap и когда он нужен",
                "cmd: journalctl — логи сервисов",
            },
        },
        {
            ID:    "git",
            Title: "Git",
            Desc:  "От init и первого коммита до rebase, конфликтов и bisect.",
            Syllabus: []string{
                "cmd: git init, config, первый коммит",
                "cmd: status, log, diff — читаем состояние репозитория",
                "cmd: .gitignore и незакоммиченный мусор",
                "cmd: ветки: branch, switch",
                "cmd: merge и разрешение конфликтов руками",
                "quiz: merge против rebase",
                "cmd: rebase и squash коммитов",
                "cmd: remote: clone, push, pull, fetch",
                "cmd: флоу фича-веток и pull request",
                "quiz: fast-forward против настоящего merge",
                "cmd: stash, restore, reset --soft/mixed/hard",
                "quiz: reset против revert — что безопаснее в общей ветке",
                "cmd: revert и cherry-pick",
                "cmd: теги и релизы",
                "quiz: HEAD и detached HEAD",
                "cmd: git bisect — ищем сломавший коммит",
                "cmd: git hooks: pre-commit",
                "cmd: gitignore-стратегии для разных стеков",
            },
        },
    }
}

// ---------- 15 встроенных задач Docker ----------

func builtinTasks() []Task {
    return []Task{
        {
            ID: "hello-world", Title: "Hello, Docker!",
            Theory: []string{
                "Docker упаковывает приложение вместе с окружением в **контейнер** — изолированную коробочку со своей файловой системой, библиотеками и процессами. Контейнер ведёт себя одинаково на любой машине с Linux-ядром, поэтому фраза «а у меня работало» наконец уходит в прошлое.",
                "Главная сущность — **образ** (image): неизменяемый шаблон, что-то вроде снимка файловой системы плюс инструкция, как запуститься. Образы лежат в реестрах; самый известный — Docker Hub.",
                "Команда `docker run` делает сразу три шага: скачает образ, если его нет локально (pull), создаст контейнер (create) и запустит его (start):",
                "```\ndocker run hello-world\n```",
                "Классика первой проверки — образ `hello-world`: он печатает приветствие и объясняет, что только что произошло. Полезные команды рядом: `docker ps` — запущенные контейнеры, `docker ps -a` — все, `docker images` — локальные образы.",
            },
            Quiz: []QuizQ{
                {Question: "Что делает docker run, если образа нет локально?",
                    Options: []string{"Скачает образ (pull), затем создаст и запустит контейнер", "Выведет ошибку и завершится", "Запустит контейнер без образа"}, Correct: 0},
                {Question: "Какая команда покажет ВСЕ контейнеры, включая остановленные?",
                    Options: []string{"docker ps", "docker ps -a", "docker images"}, Correct: 1},
            },
            Goal: "Выполни docker run hello-world и получи приветствие от контейнера.",
            Hints: []string{
                "Образ скачается сам — просто набери команду целиком: docker run hello-world",
                "Если видишь «Unable to find image…» и загрузку — это нормальный pull, дождись окончания.",
            },
            Check: "в state.images есть hello-world:latest и существует контейнер с образом hello-world (статус exited — норм)",
            Start: baseState(),
        },
        {
            ID: "run-nginx", Title: "Веб-сервер в фоне",
            Theory: []string{
                "nginx — самый популярный веб-сервер, и его официальный образ готов к работе из коробки: скачал, запустил — слушает порт 80. Флаг `-d` (`--detach`) отправляет контейнер в фон и возвращает тебе терминал:",
                "```\ndocker run -d nginx\n```",
                "Флаг `-p ХОСТ:КОНТЕЙНЕР` публикует порт: запросы на порт 8080 твоей машины улетают на порт 80 внутри контейнера. Без `-p` контейнер недостижим снаружи — сетевая изоляция по умолчанию железная.",
                "`--name` задаёт понятное имя (иначе Docker придумает случайное вроде `nostalgic_turing`):",
                "```\ndocker run -d --name web -p 8080:80 nginx\n```",
                "Контролируй результат через `docker ps` — там имена, образы, статусы и проброс портов.",
            },
            Quiz: []QuizQ{
                {Question: "Что делает флаг -p 8080:80?",
                    Options: []string{"Публикует порт 8080 хоста на порт 80 контейнера", "Меняет порт внутри контейнера на 8080", "Открывает порт 80 на хосте"}, Correct: 0},
                {Question: "Как задать контейнеру имя web?",
                    Options: []string{"--name web", "--hostname web", "docker rename web"}, Correct: 0},
            },
            Goal: "Запусти nginx в фоновом режиме: имя контейнера — web, порт 8080 хоста проброшен на 80 контейнера.",
            Hints: []string{
                "Флаги собираются в одну команду: docker run -d --name web -p 8080:80 nginx",
                "Проверь себя: docker ps — в строке web должно быть 0.0.0.0:8080->80/tcp.",
            },
            Check: "существует контейнер web с образом nginx (любой тег), status=running, в ports есть '8080->80'",
            Start: baseState(),
        },
        {
            ID: "exec", Title: "Заглянуть внутрь",
            Theory: []string{
                "Контейнер — не чёрный ящик. `docker exec` выполняет команду внутри уже работающего контейнера: от быстрого `ls` до полноценного shell:",
                "```\ndocker exec web ls /tmp\ndocker exec -it web sh\n```",
                "Связка `-it` — это interactive + tty: выделяется псевдотерминал, работают стрелки и автодополнение. В лёгких образах на базе alpine нет bash — там живёт `sh`, и этого достаточно.",
                "Всё, что ты создаёшь внутри контейнера, попадает в его временный слой записи и исчезает вместе с контейнером (`docker rm`). Поэтому для данных есть тома, а exec — для осмотра и точечных действий.",
            },
            Quiz: []QuizQ{
                {Question: "Зачем флаги -it в docker exec?",
                    Options: []string{"Выделяют интерактивный псевдотерминал", "Запускают контейнер в фоне", "Задают имя контейнера"}, Correct: 0},
                {Question: "Какой shell есть в alpine-образах?",
                    Options: []string{"bash", "sh", "zsh"}, Correct: 1},
            },
            Goal: "Контейнер web уже запущен. Выполни команду внутри него, которая создаст файл /tmp/alive (например, docker exec web touch /tmp/alive).",
            Hints: []string{
                "Сначала загляни: docker exec web ls /tmp",
                "Создание файла: docker exec web touch /tmp/alive",
            },
            Check: "контейнер web в статусе running; в его execs есть команда, создающая /tmp/alive",
            Start: func() SandboxState {
                s := baseState()
                s.Images["nginx:alpine"] = pulled("nginx", "alpine", 23)
                s.Containers["web"] = running("web", "nginx:alpine", "8080->80/tcp")
                return s
            }(),
        },
        {
            ID: "logs", Title: "Кто шумит в логах",
            Theory: []string{
                "Контейнер пишет в stdout/stderr — Docker перехватывает поток и хранит как логи. `docker logs` показывает их целиком, `--tail N` — последние N строк, `-f` — следить в реальном времени (выход — Ctrl+C):",
                "```\ndocker logs logger\ndocker logs --tail 20 logger\n```",
                "Логи — первое место диагностики: упало приложение, контейнер циклится, nginx отдаёт 404 — всё начинается здесь. Статус из `docker ps` подскажет направление: `restarting` или `exited` — тревожные знаки.",
                "Привычка профессионала: перед тем как что-то чинить, посмотреть хвост логов. Половина «мистических» проблем рассыпается на первой же строке ошибки.",
            },
            Quiz: []QuizQ{
                {Question: "Что покажет docker logs --tail 20 logger?",
                    Options: []string{"Последние 20 строк логов", "Первые 20 строк логов", "Логи за последние 20 минут"}, Correct: 0},
                {Question: "Куда приложение должно писать, чтобы логи попали в docker logs?",
                    Options: []string{"В файл внутри контейнера", "В stdout/stderr", "В syslog хоста"}, Correct: 1},
            },
            Goal: "Контейнер logger что-то печатает в stdout. Посмотри его логи, а затем останови контейнер: docker stop logger.",
            Hints: []string{
                "docker logs logger — увидеть, что он пишет.",
                "Убедился, что жив? docker stop logger — и проверь статус через docker ps -a.",
            },
            Check: "у контейнера logger logs_viewed=true (логи просматривались) и итоговый статус exited",
            Start: func() SandboxState {
                s := baseState()
                s.Images["logger:latest"] = pulled("logger", "latest", 8)
                s.Containers["logger"] = running("logger", "logger:latest", "")
                return s
            }(),
        },
        {
            ID: "build-basics", Title: "Свой первый образ",
            Theory: []string{
                "Dockerfile — рецепт образа. Каждая инструкция создаёт слой: `FROM` выбирает базу, `COPY` кладёт файлы из контекста сборки, `RUN` выполняет команды во время сборки, `CMD` говорит, что запускать по умолчанию:",
                "```\nFROM python:3.12-slim\nCOPY app.py .\nCMD [\"python\", \"app.py\"]\n```",
                "Собирается так — точка в конце это путь к контексту сборки, а не случайный символ:",
                "```\ndocker build -t myapp:1.0 .\n```",
                "Слои кэшируются: если инструкция и её входы не менялись, Docker переиспользует результат. Тег `slim` — компактная вариация базового образа без лишних пакетов.",
            },
            Quiz: []QuizQ{
                {Question: "Что означает точка в docker build -t app . ?",
                    Options: []string{"Путь к контексту сборки", "Имя Dockerfile", "Тег по умолчанию"}, Correct: 0},
                {Question: "Какая инструкция задаёт команду по умолчанию?",
                    Options: []string{"RUN", "CMD", "FROM"}, Correct: 1},
            },
            Goal: "В песочнице лежит app.py. Создай Dockerfile (база python:3.12-slim, скопируй app.py, CMD запускает его) и собери образ myapp:1.0.",
            Hints: []string{
                "Записать Dockerfile можно heredoc'ом: cat > Dockerfile <<EOF … EOF (в симуляторе это работает).",
                "Сборка: docker build -t myapp:1.0 . — не забудь точку в конце.",
            },
            Check: "в files есть Dockerfile с FROM python и COPY app.py; в state.images есть myapp:1.0",
            Start: func() SandboxState {
                s := baseState()
                s.Files["app.py"] = "import http.server\n\nprint('serving on 8000')\nhttp.server.HTTPServer(('', 8000), http.server.SimpleHTTPRequestHandler).serve_forever()\n"
                return s
            }(),
        },
        {
            ID: "copy-order", Title: "COPY и порядок слоёв",
            Theory: []string{
                "`COPY` переносит файлы из контекста сборки в слой образа: `COPY что_на_хосте куда_в_образе`. В отличие от `ADD` он делает ровно одну вещь и не распаковывает архивы — за явность платим удобством, и это честная сделка.",
                "Каждая `COPY` фиксирует состояние файлов в отдельном слое. Изменился файл — кэш инвалидируется от этого слоя и вниз. Этим пользуются: сначала копируют редко меняющиеся зависимости, ставят их, и только потом — часто правимый код:",
                "```\nCOPY requirements.txt .\nRUN pip install -r requirements.txt\nCOPY app.py .\n```",
                "Явные пути лучше `COPY . .`: не тащишь в образ мусор из папки (логи, .git, секреты). Для фильтрации существует `.dockerignore`, но аккуратный COPY — уже половина дела.",
            },
            Quiz: []QuizQ{
                {Question: "Почему COPY requirements.txt делают до COPY app.py?",
                    Options: []string{"Чтобы кэш зависимостей не инвалидовался при правках кода", "Так требует синтаксис Dockerfile", "Чтобы уменьшить число слоёв"}, Correct: 0},
                {Question: "Чем COPY отличается от ADD?",
                    Options: []string{"ADD распаковывает архивы и умеет URL, COPY просто копирует", "Ничем, это синонимы", "COPY работает только с папками"}, Correct: 0},
            },
            Goal: "В песочнице app.py и requirements.txt. Напиши Dockerfile: база python:3.12-slim; отдельные COPY для requirements.txt и app.py в /app; установка зависимостей pip'ом; CMD python /app/app.py. Собери образ site:2.0.",
            Hints: []string{
                "Порядок: COPY requirements.txt → RUN pip install → COPY app.py. Тогда правки кода не будут переустанавливать зависимости.",
                "Собери: docker build -t site:2.0 .",
            },
            Check: "в files Dockerfile содержит два COPY (requirements.txt и app.py) и pip install; в state.images есть site:2.0",
            Start: func() SandboxState {
                s := baseState()
                s.Files["app.py"] = "from flask import Flask\napp = Flask(__name__)\n\n@app.route('/')\ndef home():\n    return 'site works'\n\napp.run(host='0.0.0.0', port=8000)\n"
                s.Files["requirements.txt"] = "flask==3.0.0\n"
                return s
            }(),
        },
        {
            ID: "env", Title: "Переменные окружения",
            Theory: []string{
                "`ENV` задаёт переменную окружения прямо в образе: она доступна и во время сборки (следующим RUN), и внутри работающего контейнера. Так конфигурируют приложения, не трогая код: `APP_ENV`, `PORT`, `DATABASE_URL`.",
                "```\nENV APP_ENV=production\nENV PORT=8000\n```",
                "Значение легко переопределить при запуске — образ остаётся тем же, поведение меняется:",
                "```\ndocker run -e PORT=9000 myapp:1.0\n```",
                "Это философия twelve-factor: конфигурация живёт в окружении, а не в файлах. Посмотреть переменные внутри контейнера можно командой `env` или `printenv`.",
            },
            Quiz: []QuizQ{
                {Question: "Как переопределить переменную ENV при запуске?",
                    Options: []string{"docker run -e PORT=9000 …", "Через правку Dockerfile", "Никак, ENV неизменяема"}, Correct: 0},
                {Question: "Где доступна переменная, заданная ENV?",
                    Options: []string{"Только при сборке", "Только в рантайме", "И при сборке, и в контейнере"}, Correct: 2},
            },
            Goal: "Напиши Dockerfile для образа envapp:1.0: база python:3.12-slim, ENV APP_ENV=production, ENV PORT=8000, скопируй app.py, CMD запускает python app.py. Собери образ.",
            Hints: []string{
                "ENV-строки ставятся в Dockerfile до CMD: ENV APP_ENV=production",
                "Проверка: docker run --rm envapp:1.0 env — в выводе должны быть обе переменные.",
            },
            Check: "в state.images есть envapp:1.0; в его env есть APP_ENV=production и PORT=8000; в files Dockerfile содержит ENV",
            Start: func() SandboxState {
                s := baseState()
                s.Files["app.py"] = "import os\n\nprint('APP_ENV =', os.environ.get('APP_ENV'))\nprint('PORT =', os.environ.get('PORT'))\n"
                return s
            }(),
        },
        {
            ID: "volumes", Title: "Данные переживают контейнер",
            Theory: []string{
                "Слой записи контейнера одноразовый: удалил контейнер — удалились и данные. **Том** (volume) — управляемая Docker область на хосте, которую подключают в контейнер флагом `-v`:",
                "```\ndocker volume create appdata\ndocker run -d --name data-writer -v appdata:/data alpine …\n```",
                "Живёт том независимо от контейнеров: пересоздавай контейнер сколько хочешь — данные на месте. Инвентарь: `docker volume ls`, `docker volume inspect`, `docker volume rm`.",
                "Анонимные тома (без имени) — источник мусора, поэтому всегда называй явно.",
            },
            Quiz: []QuizQ{
                {Question: "Что происходит с данными именованного тома при удалении контейнера?",
                    Options: []string{"Том остаётся на месте", "Удаляются вместе с контейнером", "Том пересоздаётся пустым"}, Correct: 0},
                {Question: "Как смонтировать именованный том appdata в /data?",
                    Options: []string{"-v appdata:/data", "--volume-name appdata", "-m appdata"}, Correct: 0},
            },
            Goal: "Создай том appdata и запусти контейнер data-writer (образ alpine), который каждые 5 секунд дописывает дату в /data/log.txt, с монтированием appdata в /data.",
            Hints: []string{
                "Сначала том: docker volume create appdata",
                "Затем: docker run -d --name data-writer -v appdata:/data alpine sh -c 'while true; do date >> /data/log.txt; sleep 5; done'",
            },
            Check: "в state.volumes есть appdata; контейнер data-writer running и в его mounts есть 'appdata:/data'",
            Start: func() SandboxState {
                s := baseState()
                s.Images["alpine:latest"] = pulled("alpine", "latest", 7)
                return s
            }(),
        },
        {
            ID: "networks", Title: "Сети: разговариваем по имени",
            Theory: []string{
                "По умолчанию контейнеры сидят в bridge-сети и видят друг друга по IP-адресам, но не по именам. Пользовательская сеть добавляет встроенный DNS: контейнер `cache` доступен соседям просто по имени `cache`.",
                "```\ndocker network create appnet\ndocker run -d --name cache --network appnet redis:alpine\n```",
                "Один контейнер может состоять в нескольких сетях сразу. Это фундамент микросервисов: web ходит к db по имени `db` — никаких IP и никаких правок конфигов при пересоздании контейнеров.",
            },
            Quiz: []QuizQ{
                {Question: "Что даёт пользовательская сеть по сравнению с bridge по умолчанию?",
                    Options: []string{"Встроенный DNS: контейнеры видны по имени", "Ускоряет сеть вдвое", "Полностью изолирует от интернета"}, Correct: 0},
                {Question: "Как подключить контейнер к сети appnet при запуске?",
                    Options: []string{"--network appnet", "--dns appnet", "--link appnet"}, Correct: 0},
            },
            Goal: "Создай сеть appnet и запусти в ней два контейнера: cache (образ redis:alpine) и front (образ nginx:alpine).",
            Hints: []string{
                "docker network create appnet",
                "docker run -d --name cache --network appnet redis:alpine — и то же самое для front с nginx:alpine.",
            },
            Check: "в state.networks есть appnet; контейнеры cache и front оба running и у обоих в networks есть appnet",
            Start: func() SandboxState {
                s := baseState()
                s.Images["redis:alpine"] = pulled("redis", "alpine", 15)
                s.Images["nginx:alpine"] = pulled("nginx", "alpine", 23)
                return s
            }(),
        },
        {
            ID: "multi-stage", Title: "Многоступенчатая сборка",
            Theory: []string{
                "В образе для сборки живёт много лишнего: компиляторы, кэши, dev-зависимости. **Multi-stage** сборка решает это элегантно: собираем артефакт в одном образе и переносим в чистый финальный. У каждой ступени своё имя:",
                "```\nFROM golang:1.22 AS build\nRUN go build -o /server .\n\nFROM alpine:3.19\nCOPY --from=build /server /server\nCMD [\"/server\"]\n```",
                "Финальным считается последний `FROM`. Копировать из ступени в ступень умеет `COPY --from=имя`.",
                "Результат драматичный: Go-приложение может весить 700+ МБ в сборщике и ~10 МБ в рантайме на alpine. Быстрее деплой, меньше поверхность атаки, проще распространение.",
            },
            Quiz: []QuizQ{
                {Question: "Зачем в Dockerfile несколько FROM?",
                    Options: []string{"Собрать артефакт в одном образе и перенести в чистый финальный", "Чтобы слоёв было больше", "Так ускоряется сборка"}, Correct: 0},
                {Question: "Как скопировать файл из ступени build?",
                    Options: []string{"COPY --from=build /server /server", "COPY build:/server /server", "GET --stage build /server"}, Correct: 0},
            },
            Goal: "В песочнице main.go — маленький HTTP-сервер на Go. Напиши Dockerfile с двумя ступенями: golang:1.22 (сборка) и alpine:3.19 (рантайм); скопируй собранный бинарник. Собери образ myapi:1.0.",
            Hints: []string{
                "Первая ступень: FROM golang:1.22 AS build … RUN go build -o /server .",
                "Вторая ступень: FROM alpine:3.19 … COPY --from=build /server /server … CMD [\"/server\"]",
            },
            Check: "в state.images есть myapi:1.0; в его layers минимум два FROM, последний — alpine, и присутствует COPY --from",
            Start: func() SandboxState {
                s := baseState()
                s.Files["main.go"] = "package main\n\nimport (\n\t\"fmt\"\n\t\"net/http\"\n)\n\nfunc main() {\n\thttp.HandleFunc(\"/\", func(w http.ResponseWriter, r *http.Request) {\n\t\tfmt.Fprintln(w, \"api ok\")\n\t})\n\thttp.ListenAndServe(\":8080\", nil)\n}\n"
                s.Files["go.mod"] = "module myapi\n\ngo 1.22\n"
                return s
            }(),
        },
        {
            ID: "compose", Title: "Compose: оркестр в одном файле",
            Theory: []string{
                "Когда контейнеров становится несколько, флаги в CLI превращаются в заклинание. `docker-compose.yml` описывает все сервисы декларативно — и вся инфраструктура поднимается одной командой:",
                "```yaml\nservices:\n  web:\n    image: nginx:alpine\n    ports:\n      - \"8081:80\"\n  db:\n    image: redis:alpine\n```",
                "`docker compose up -d` создаёт недостающие контейнеры и общую сеть проекта; `docker compose down` гасит и убирает. Это YAML — отступы значат то же, что скобки в коде.",
                "Современный compose — плагин к docker CLI: `docker compose` (пробел, без дефиса). Старый `docker-compose` ещё встречается в туториалах, но пиши по-новому.",
            },
            Quiz: []QuizQ{
                {Question: "Какой синтаксис считается современным?",
                    Options: []string{"docker compose up -d", "docker-compose up -d", "docker up compose"}, Correct: 0},
                {Question: "Что делает docker compose down?",
                    Options: []string{"Останавливает и удаляет контейнеры проекта", "Только останавливает, не удаляет", "Удаляет образы с диска"}, Correct: 0},
            },
            Goal: "Напиши docker-compose.yml с двумя сервисами: web (образ nginx:alpine, порт 8081:80) и db (образ redis:alpine). Подними их: docker compose up -d.",
            Hints: []string{
                "Каркас: services: → web: → image: nginx:alpine → ports: → - \"8081:80\" (отступы — 2 пробела).",
                "Второй сервис db описывается так же, только порт не нужен. Потом docker compose up -d.",
            },
            Check: "в files есть docker-compose.yml с сервисами web и db; запущены контейнеры обоих сервисов",
            Start: func() SandboxState {
                s := baseState()
                s.Images["nginx:alpine"] = pulled("nginx", "alpine", 23)
                s.Images["redis:alpine"] = pulled("redis", "alpine", 15)
                return s
            }(),
        },
        {
            ID: "depends-on", Title: "Кто первый встал — того и ботинки",
            Theory: []string{
                "Классическая боль: приложение стартует раньше базы и падает, потому что подключиться некуда. `depends_on` в compose объявляет порядок: сначала зависимости, потом зависящие.",
                "Но простой `depends_on` ждёт лишь запуска контейнера, а не готовности сервиса. Решение — `healthcheck` у базы (команда-проверка живости) и `depends_on` с условием:",
                "```yaml\n  db:\n    image: redis:alpine\n    healthcheck:\n      test: [\"CMD\", \"redis-cli\", \"ping\"]\n      interval: 5s\n  app:\n    image: nginx:alpine\n    depends_on:\n      db:\n        condition: service_healthy\n```",
                "Redis умеет отвечать на `redis-cli ping` — идеальный healthcheck. Для Postgres обычно `pg_isready`, для web — `curl` на /health.",
            },
            Quiz: []QuizQ{
                {Question: "Простой depends_on гарантирует…",
                    Options: []string{"Только запуск контейнера, не готовность сервиса", "Полную готовность сервиса", "Здоровье зависимости"}, Correct: 0},
                {Question: "Какое condition ждёт готовности healthcheck?",
                    Options: []string{"service_healthy", "service_started", "service_complete"}, Correct: 0},
            },
            Goal: "В песочнице есть docker-compose.yml с сервисом db (redis). Добавь healthcheck к db (redis-cli ping) и сервис app (образ nginx:alpine, порт 8082:80) с depends_on на db и условием service_healthy. Подними: docker compose up -d.",
            Hints: []string{
                "healthcheck: test: [\"CMD\", \"redis-cli\", \"ping\"], interval: 5s",
                "depends_on: db: condition: service_healthy — с правильными отступами внутри сервиса app.",
            },
            Check: "в docker-compose.yml у db есть healthcheck, у app есть depends_on с condition: service_healthy; контейнеры app и db запущены",
            Start: func() SandboxState {
                s := baseState()
                s.Images["redis:alpine"] = pulled("redis", "alpine", 15)
                s.Images["nginx:alpine"] = pulled("nginx", "alpine", 23)
                s.Files["docker-compose.yml"] = "services:\n  db:\n    image: redis:alpine\n"
                return s
            }(),
        },
        {
            ID: "optimize", Title: "Похудение образа",
            Theory: []string{
                "Каждый `RUN` — отдельный слой, а удалённые в следующем слое файлы продолжают занимать место в предыдущем. Поэтому установку пакетов и очистку объединяют в ОДИН RUN:",
                "```\nRUN apt-get update && apt-get install -y --no-install-recommends curl \\\n    && rm -rf /var/lib/apt/lists/*\n```",
                "Самый большой выигрыш даёт базовый образ: `ubuntu` ~78 МБ, `alpine` ~7 МБ, `python:3.12-slim` ~55 МБ против `python:3.12` ~1 ГБ. Сменил одну строку FROM — минус сотни мегабайт.",
                "Связка «компактная база + объединённые RUN + multi-stage» превращает гигантский образ в аккуратный артефакт, который качается за секунды.",
            },
            Quiz: []QuizQ{
                {Question: "Почему rm -rf /var/lib/apt/lists в следующем RUN не уменьшает образ?",
                    Options: []string{"Удалённые файлы остаются в предыдущем слое", "rm не работает в Dockerfile", "Слой сжимается при сборке"}, Correct: 0},
                {Question: "Самый компактный базовый образ из перечисленных?",
                    Options: []string{"ubuntu:22.04", "alpine", "debian:bookworm"}, Correct: 1},
            },
            Goal: "В песочнице тяжёлый Dockerfile — из него собран big:1.0 на 780 МБ. Перепиши его: база python:3.12-slim, компактные слои (apt — одним RUN с очисткой кэша, или вовсе без apt), и собери small:1.0 размером меньше 150 МБ.",
            Hints: []string{
                "python:3.12-slim уже умеет запускать .py — возможно, apt тебе вообще не нужен.",
                "Если apt нужен: RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*",
            },
            Check: "в state.images есть small:1.0 с size_mb меньше 150; база (первый FROM) — python:3.12-slim",
            Start: func() SandboxState {
                s := baseState()
                s.Files["app.py"] = "print('hello from heavy image')\n"
                s.Files["Dockerfile"] = "FROM ubuntu:22.04\nRUN apt-get update && apt-get install -y python3 python3-pip curl vim build-essential\nCOPY app.py /app/\nCMD [\"python3\", \"/app/app.py\"]\n"
                big := pulled("big", "1.0", 780)
                big.Layers = []string{
                    "FROM ubuntu:22.04",
                    "RUN apt-get update && apt-get install -y python3 python3-pip curl vim build-essential",
                    "COPY app.py /app/",
                    "CMD [\"python3\", \"/app/app.py\"]",
                }
                s.Images["big:1.0"] = big
                return s
            }(),
        },
        {
            ID: "entrypoint-cmd", Title: "ENTRYPOINT против CMD",
            Theory: []string{
                "`CMD` задаёт команду по умолчанию: `docker run образ арг` полностью заменяет её. `ENTRYPOINT` — фиксированная программа: аргументы приписываются к ней, а не заменяют её.",
                "Паттерн «инструмент» — фиксируем программу, отдаём аргументы пользователю:",
                "```\nENTRYPOINT [\"curl\"]\nCMD [\"--help\"]\n```",
                "Тогда `docker run img https://example.org` вызовет curl с этим адресом, а `docker run img --version` — curl --version. Гибко и предсказуемо.",
                "Пиши обе инструкции в exec-форме — JSON-массивом. Shell-форма (строкой) оборачивает всё в `/bin/sh -c` и ломает обработку сигналов — контейнер перестаёт корректно реагировать на `docker stop`.",
            },
            Quiz: []QuizQ{
                {Question: "Что произойдёт с CMD при docker run img аргументы?",
                    Options: []string{"Заменится аргументами", "Допишется к ENTRYPOINT", "Будет проигнорирован ошибкой"}, Correct: 0},
                {Question: "Зачем exec-форма (JSON-массив) для CMD/ENTRYPOINT?",
                    Options: []string{"Корректная обработка сигналов — docker stop работает", "Так красивее в логах", "Контейнер стартует быстрее"}, Correct: 0},
            },
            Goal: "Собери образ greeter:1.0 (база alpine; ENTRYPOINT [\"/bin/sh\", \"-c\"]; CMD [\"echo hello from greeter\"]). Запусти его без аргументов, а затем — с переопределением: docker run --rm greeter:1.0 echo overridden.",
            Hints: []string{
                "Dockerfile: FROM alpine:3.19, затем ENTRYPOINT [\"/bin/sh\", \"-c\"] и CMD [\"echo hello from greeter\"].",
                "Собери: docker build -t greeter:1.0 . Запусти без аргументов, потом — docker run --rm greeter:1.0 echo overridden.",
            },
            Check: "в state.images есть greeter:1.0; в его entrypoint есть '/bin/sh', в cmd есть 'echo hello'; в state.events есть запуск с переопределённым cmd",
            Start: func() SandboxState {
                s := baseState()
                s.Images["alpine:3.19"] = pulled("alpine", "3.19", 7)
                return s
            }(),
        },
        {
            ID: "debug-broken", Title: "Разбор полётов",
            Theory: []string{
                "Типичные причины «контейнер не стартует»: опечатка в имени файла (`COPY app.pyy` вместо `app.py`), неверный путь в `CMD`, отсутствие нужного пакета. Симптомы: статус `exited` с кодом 1 или бесконечный `restarting`.",
                "Диагностика по шагам:",
                "```\ndocker ps -a          # статус и код выхода\ndocker logs job       # что сказал процесс перед смертью\ndocker run -it образ sh   # залезть внутрь и осмотреться\n```",
                "Читайте ошибки буквально: «COPY failed: file not found» означает ровно отсутствие файла в контексте сборки. Обычно исправление — одна строка в Dockerfile.",
                "Правило: меняешь Dockerfile — пересобирай образ. Запущенный контейнер не обновится сам: образ иммутабелен, контейнер — лишь его экземпляр.",
            },
            Quiz: []QuizQ{
                {Question: "Первое место диагностики упавшего контейнера?",
                    Options: []string{"docker logs", "docker rm", "docker pull"}, Correct: 0},
                {Question: "Ты исправил Dockerfile — что дальше?",
                    Options: []string{"Пересобрать образ (docker build)", "Просто перезапустить старый контейнер", "Ничего, контейнер обновится сам"}, Correct: 0},
            },
            Goal: "Контейнер job из образа broken:1.0 падает при старте. Найди ошибки в Dockerfile (опечатка в COPY и неверный путь в CMD), исправь файл, пересобери образ как fixed:1.0 и запусти контейнер job из него.",
            Hints: []string{
                "docker logs job покажет что-то вроде «can't open file '/app/main.py'» — а файл-то называется app.py.",
                "Исправь Dockerfile: COPY app.py /app/ и CMD [\"python\", \"/app/app.py\"]. Пересобери: docker build -t fixed:1.0 .",
            },
            Check: "в files Dockerfile исправлен (COPY app.py без опечатки, CMD указывает на app.py); в state.images есть fixed:1.0; контейнер job работает из fixed:1.0 со статусом running",
            Start: func() SandboxState {
                s := baseState()
                s.Files["app.py"] = "print('now it works')\n"
                s.Files["Dockerfile"] = "FROM python:3.12-slim\nWORKDIR /app\nCOPY app.pyy /app/\nCMD [\"python\", \"/app/main.py\"]\n"
                broken := pulled("broken", "1.0", 55)
                broken.Layers = []string{"FROM python:3.12-slim", "WORKDIR /app", "COPY app.pyy /app/", "CMD [\"python\", \"/app/main.py\"]"}
                s.Images["broken:1.0"] = broken
                s.Images["python:3.12-slim"] = pulled("python", "3.12-slim", 55)
                j := running("job", "broken:1.0", "")
                j.Status = "exited"
                s.Containers["job"] = j
                return s
            }(),
        },
    }
}
