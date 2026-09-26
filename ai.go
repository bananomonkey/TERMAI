// ai.go — клиент DeepSeek и пять ролей: симулятор (практика+тесты), проверяющий
// по истории терминала (с объективной сложностью), ментор, генератор задач
// (теория markdown + тест + практика, поддержка указаний по стилю) и генератор курсов.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	openai "github.com/sashabaranov/go-openai"
)

// ---------- провайдеры (все — через OpenAI-совместимый API) ----------

type Provider struct {
	ID           string
	Title        string
	BaseURL      string
	DefaultModel string
	Models       []string
	NeedsKey     bool
}

// providers — пресеты. Любой провайдер с OpenAI-совместимым endpoint поддерживается;
// для «custom» пользователь задаёт BaseURL и модель вручную.
var providers = []Provider{
	{ID: "deepseek", Title: "DeepSeek", BaseURL: "https://api.deepseek.com", DefaultModel: "deepseek-chat",
		Models: []string{"deepseek-chat", "deepseek-reasoner"}, NeedsKey: true},
	{ID: "openai", Title: "OpenAI", BaseURL: "https://api.openai.com/v1", DefaultModel: "gpt-4o-mini",
		Models: []string{"gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1", "o3-mini"}, NeedsKey: true},
	{ID: "gemini", Title: "Google Gemini", BaseURL: "https://generativelanguage.googleapis.com/v1beta/openai/", DefaultModel: "gemini-2.0-flash",
		Models: []string{"gemini-2.0-flash", "gemini-2.5-flash", "gemini-2.5-pro"}, NeedsKey: true},
	{ID: "qwen", Title: "Qwen (DashScope)", BaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", DefaultModel: "qwen-plus",
		Models: []string{"qwen-plus", "qwen-max", "qwen-turbo", "qwen2.5-72b-instruct", "qwen3-235b-a22b"}, NeedsKey: true},
	{ID: "openrouter", Title: "OpenRouter", BaseURL: "https://openrouter.ai/api/v1", DefaultModel: "deepseek/deepseek-chat",
		Models: []string{"deepseek/deepseek-chat", "deepseek/deepseek-r1", "anthropic/claude-3.5-sonnet", "qwen/qwen-2.5-72b-instruct", "meta-llama/llama-3.3-70b-instruct"}, NeedsKey: true},
	{ID: "groq", Title: "Groq", BaseURL: "https://api.groq.com/openai/v1", DefaultModel: "llama-3.3-70b-versatile",
		Models: []string{"llama-3.3-70b-versatile", "llama-3.1-8b-instant", "qwen-qwq-32b"}, NeedsKey: true},
	{ID: "mistral", Title: "Mistral", BaseURL: "https://api.mistral.ai/v1", DefaultModel: "mistral-large-latest",
		Models: []string{"mistral-large-latest", "mistral-small-latest", "codestral-latest"}, NeedsKey: true},
	{ID: "ollama", Title: "Ollama (локально)", BaseURL: "http://localhost:11434/v1", DefaultModel: "llama3.1",
		Models: []string{"llama3.1", "llama3.2", "qwen2.5", "mistral", "gemma2"}, NeedsKey: false},
	{ID: "custom", Title: "Свой (OpenAI-совместимый)", BaseURL: "", DefaultModel: "", Models: nil, NeedsKey: false},
}

func findProvider(id string) Provider {
	for _, p := range providers {
		if p.ID == id {
			return p
		}
	}
	return providers[0]
}

func providerTitles() []string {
	out := make([]string, len(providers))
	for i, p := range providers {
		out[i] = p.Title
	}
	return out
}

func providerIDByTitle(title string) string {
	for _, p := range providers {
		if p.Title == title {
			return p.ID
		}
	}
	return "deepseek"
}

func hasString(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

// visionModelSupported — умеет ли выбранная модель принимать изображения
// (multimodal). Определяем по провайдеру и имени модели; для custom/openrouter
// смотрим на известные маркеры в имени.
func visionModelSupported(providerID, model string) bool {
	m := strings.ToLower(strings.TrimSpace(model))
	switch providerID {
	case "deepseek":
		return false
	case "openai":
		return strings.Contains(m, "gpt-4o") || strings.Contains(m, "gpt-4.1") ||
			strings.Contains(m, "gpt-4-turbo") || strings.Contains(m, "o3") ||
			strings.Contains(m, "o4") || strings.Contains(m, "gpt-5")
	case "gemini":
		return true
	case "qwen":
		return strings.Contains(m, "vl")
	case "groq":
		return strings.Contains(m, "vision")
	case "mistral":
		return strings.Contains(m, "pixtral")
	case "ollama", "openrouter", "custom":
		for _, mark := range []string{"vision", "vl", "llava", "claude", "gemini", "gpt-4o", "gpt-5", "pixtral", "qwen2.5-vl", "qwen-vl"} {
			if strings.Contains(m, mark) {
				return true
			}
		}
		return false
	}
	return false
}

type AIClient struct {
	cli   *openai.Client
	model string
}

// NewAIClient собирает клиент из настроек: провайдер, ключ, базовый URL, модель.
// Незаданные BaseURL/Model берутся из пресета провайдера.
func NewAIClient(cfg *Config) *AIClient {
	if cfg == nil {
		return nil
	}
	prov := findProvider(cfg.Provider)
	base := strings.TrimSpace(cfg.BaseURL)
	if base == "" {
		base = prov.BaseURL
	}
	model := strings.TrimSpace(cfg.Model)
	if model == "" {
		model = prov.DefaultModel
	}
	key := strings.TrimSpace(cfg.APIKey)
	if key == "" && (prov.ID == "ollama" || strings.Contains(base, "localhost") || strings.Contains(base, "127.0.0.1")) {
		key = "local" // локальным серверам не нужен ключ, но клиенту нужна непустая строка
	}
	if key == "" || base == "" || model == "" {
		return nil
	}
	oc := openai.DefaultConfig(key)
	oc.BaseURL = base
	return &AIClient{cli: openai.NewClientWithConfig(oc), model: model}
}

// ---------- роль 1: симулятор ----------

const sysSimulator = `Ты — симулятор терминала Linux с установленным Docker и Git внутри учебного тренажёра. Ты не настоящий терминал: ты вычисляешь правдоподобный вывод команд и поддерживаешь виртуальное состояние песочницы.

Правила:
1. Пользователь вводит ОДНУ строку. Если задача — практика (cmd), ответь тем, что напечатал бы реальный терминал: таблицы docker ps / docker images, шаги сборки, ошибки вида "docker: Error response from daemon", "bash: foo: command not found". Без markdown, без пояснений от себя.
2. Если задача — тест (quiz): ввод пользователя это ОТВЕТ НА ВОПРОС, не исполняй его как команду. Оцени ответ: верно — output "✓ Верно." и короткое пояснение (2-3 предложения), solved=true; неточно — output "✗ Не совсем." и мягкий наводящий намёк БЕЗ раскрытия правильного ответа, solved=false; совсем мимо — output "✗ Неверно." и намёк, solved=false.
3. Поддерживай состояние: docker pull/run/create/build добавляют образы и контейнеры; rm/rmi/stop/kill/start/exec/logs/volume/network/compose меняют их; bash-команды (ls, cat, echo, cd, pwd, mkdir, touch, rm, cp, mv, grep, git init/add/commit/branch/merge/…) работают с files и events. Перенаправление и heredoc (cat > file <<EOF) записывают файл. docker logs ставит logs_viewed=true у контейнера; docker exec добавляет команду в execs контейнера.
4. docker build читает Dockerfile из files, парсит FROM/RUN/COPY/ENV/WORKDIR/CMD/ENTRYPOINT/EXPOSE/HEALTHCHECK/ARG, создаёт образ: layers, env, entrypoint, cmd, size_mb правдоподобно (alpine ~7, slim ~55, ubuntu ~78, golang ~340).
5. docker run создаёт контейнер: имя из --name или случайное, status=running с -d. Порты "8080->80/tcp". -v создаёт volume и mount. --network добавляет сеть. Переопределённый CMD фиксируй в events.
6. solved=true только если задача ПОЛНОСТЬЮ выполнена. Ответ — ТОЛЬКО валидный JSON:
{"output": "...", "state": {…полное состояние…}, "solved": false}

Схема state:
{"workdir":"/workspace","files":{"путь":"содержимое"},"images":{"repo:tag":{"id":"sha256:ab12","repo":"repo","tag":"tag","size_mb":52,"env":[],"entrypoint":"","cmd":"","layers":["FROM …"]}},"containers":{"имя":{"id":"ab12cd34","name":"имя","image":"repo:tag","status":"running","ports":"8080->80/tcp","mounts":["том:/путь"],"networks":["bridge"],"execs":[],"logs_viewed":false}},"volumes":{"имя":"local"},"networks":["bridge","host","none"],"events":[]}
Возвращай state ВСЕГДА целиком.`

type SimResult struct {
	Output string       `json:"output"`
	State  SandboxState `json:"state"`
	Solved bool         `json:"solved"`
}

func formatHist(hist []HistEntry, maxOut int) string {
	if len(hist) == 0 {
		return "(пусто)"
	}
	var b strings.Builder
	for _, h := range hist {
		out := h.Out
		if len(out) > maxOut {
			out = out[:maxOut] + "…"
		}
		b.WriteString("$ " + h.Cmd + "\n" + out + "\n---\n")
	}
	return b.String()
}

func (a *AIClient) RunCommand(ctx context.Context, c *Course, task *Task, st *SandboxState, hist []HistEntry, cmd string) (SimResult, error) {
	stJSON, _ := json.Marshal(st)
	var taskDesc string
	if task == nil {
		taskDesc = "задач нет (свободный режим): solved всегда false."
	} else {
		kind := task.Kind
		if kind == "" {
			kind = taskCmd
		}
		taskDesc = fmt.Sprintf("курс: %s\nтип: %s\nцель: %s\nкритерий: %s", c.Title, kind, task.Goal, task.Check)
	}
	user := fmt.Sprintf("КУРС И ЗАДАЧА:\n%s\n\nНЕДАВНЯЯ ИСТОРИЯ ТЕРМИНАЛА:\n%s\n\nСОСТОЯНИЕ ПЕСОЧНИЦЫ (до):\n%s\n\nВВОД ПОЛЬЗОВАТЕЛЯ:\n%s\n\nВерни JSON output/state/solved.",
		taskDesc, formatHist(hist, 240), string(stJSON), cmd)

	var res SimResult
	if err := a.chatJSON(ctx, sysSimulator, user, &res, 0.0); err != nil {
		return res, err
	}
	normalizeState(&res.State)
	return res, nil
}

// ---------- роль 2: проверяющий (+ объективная сложность) ----------

const sysChecker = `Ты — строгий, но справедливый проверяющий в тренажёре (Docker/Linux/Git). Тебе дают задачу, критерий успеха, ИСТОРИЮ КОМАНД терминала студента и финальное состояние песочницы.
Задача засчитывается, только если выполнены ОБА условия:
- итоговое состояние удовлетворяет критерию;
- студент пришёл к нему сам через терминал: в истории видны осмысленные шаги, соответствующие условию (требовалось посмотреть логи — в истории был docker logs; собрать образ — docker build; и т.д.).
Если состояние подходит, но история пуста или шаги не соответствуют условию — solved=false и объясни одной фразой, чего не хватает. Учитывай эквивалентные формы флагов (-d/--detach и т.п.).
Также оцени объективную сложность 1-5: 1 — одна очевидная команда; 2 — пара команд; 3 — несколько шагов или аккуратный файл; 4 — многошаговая с конфигурацией или отладкой; 5 — комплексная.
Ответ — только JSON: {"solved": true|false, "comment": "1-2 фразы по-русски", "difficulty": 3}`

type CheckResult struct {
	Solved     bool   `json:"solved"`
	Comment    string `json:"comment"`
	Difficulty int    `json:"difficulty"`
}

func (a *AIClient) Verify(ctx context.Context, c *Course, task *Task, st *SandboxState, hist []HistEntry) (CheckResult, error) {
	stJSON, _ := json.Marshal(st)
	user := fmt.Sprintf("Курс: %s\nЗадача: %s\nУсловие: %s\nКритерий: %s\n\nИстория терминала студента:\n%s\n\nФинальное состояние:\n%s",
		c.Title, task.Title, task.Goal, task.Check, formatHist(hist, 300), string(stJSON))
	var res CheckResult
	err := a.chatJSON(ctx, sysChecker, user, &res, 0.0)
	if res.Difficulty < 1 || res.Difficulty > 5 {
		res.Difficulty = task.Difficulty
	}
	return res, err
}

// ---------- роль 3: ментор ----------

const sysMentor = "Ты — ИИ-наставник в тренажёре (Docker/Linux/Git и смежное). Стиль: тепло, по-человечески, кратко.\n" +
	"- Отвечай по-русски, обычно до 120 слов. Без эмодзи.\n" +
	"- Видишь задачу, состояние песочницы и историю команд студента — отвечай в этом контексте.\n" +
	"- Сначала подтолкни к решению: идея, наводящий вопрос. Полное решение — только по прямой просьбе («дай решение»).\n" +
	"- Если студент просит создать задачу — скажи воспользоваться кнопкой «Задача от ИИ» в шапке и описать тему там: ты не можешь создавать задачи из чата.\n" +
	"- Используй markdown умеренно: **жирный**, `код`, списки.\n" +
	"- Не выдумывай несуществующие команды и флаги."

func (a *AIClient) Mentor(ctx context.Context, c *Course, task *Task, st *SandboxState, hist []HistEntry, chatLog []string, question string, images []string) (string, error) {
	var b strings.Builder
	b.WriteString("Курс: " + c.Title + "\n")
	if task != nil {
		b.WriteString(fmt.Sprintf("Текущая задача: %s — %s\n", task.Title, task.Goal))
	}
	b.WriteString(stateSummary(st))
	b.WriteString("\nНедавние команды:\n" + formatHist(hist, 160))
	if len(chatLog) > 0 {
		b.WriteString("\nНедавний диалог:\n" + strings.Join(chatLog, "\n") + "\n")
	}
	b.WriteString("\nВопрос студента: " + question)

	userMsg := openai.ChatCompletionMessage{Role: openai.ChatMessageRoleUser, Content: b.String()}
	if len(images) > 0 {
		parts := []openai.ChatMessagePart{{Type: openai.ChatMessagePartTypeText, Text: b.String()}}
		for _, img := range images {
			parts = append(parts, openai.ChatMessagePart{
				Type:     openai.ChatMessagePartTypeImageURL,
				ImageURL: &openai.ChatMessageImageURL{URL: img},
			})
		}
		userMsg = openai.ChatCompletionMessage{Role: openai.ChatMessageRoleUser, MultiContent: parts}
	}

	resp, err := a.cli.CreateChatCompletion(ctx, openai.ChatCompletionRequest{
		Model: a.model,
		Messages: []openai.ChatCompletionMessage{
			{Role: openai.ChatMessageRoleSystem, Content: sysMentor},
			userMsg,
		},
		Temperature: 0.7,
	})
	if err != nil {
		return "", err
	}
	if len(resp.Choices) == 0 {
		return "", fmt.Errorf("пустой ответ модели")
	}
	return strings.TrimSpace(resp.Choices[0].Message.Content), nil
}

func stateSummary(st *SandboxState) string {
	files := make([]string, 0, len(st.Files))
	for f := range st.Files {
		files = append(files, f)
	}
	images := make([]string, 0, len(st.Images))
	for k := range st.Images {
		images = append(images, k)
	}
	cons := make([]string, 0, len(st.Containers))
	for n, c := range st.Containers {
		cons = append(cons, n+" ("+c.Status+")")
	}
	return fmt.Sprintf("Песочница: workdir=%s; файлы: %s; образы: %s; контейнеры: %s; томов: %d; сети: %s.\n",
		st.Workdir, orNone(files), orNone(images), orNone(cons), len(st.Volumes), strings.Join(st.Networks, ", "))
}

func orNone(items []string) string {
	if len(items) == 0 {
		return "—"
	}
	return strings.Join(items, ", ")
}

// ---------- роль 4: генератор задач ----------

const sysTaskGen = "Ты — генератор учебных задач для тренажёра (Docker/Linux/Git и смежные темы: сети, CI/CD и т.п.). Тебе дают курс, тему (префикс cmd: практика в терминале, quiz: вопрос-тест) и названия недавних задач — не повторяй их.\n" +
	"Формат задачи (как в интерактивных платформах): ТЕОРИЯ → ТЕСТ (2 вопроса по теории) → ПРАКТИКА.\n" +
	"Теория: markdown. Каждый элемент массива theory — один блок. Обязательно используй примеры команд: инлайн `код` для команд и флагов и код-блоки ``` для многострочных примеров (Dockerfile, compose, последовательности команд). Живым языком, 3-5 блоков.\n" +
	"Для kind=cmd добавь quiz — РОВНО 2 вопроса с 3 вариантами ответа, вопросы проверяют понимание теории (correct — индекс правильного варианта с 0). Для kind=quiz массив quiz оставь пустым.\n" +
	"Для cmd: практика решаемая командами в терминале симулятора; start_state содержит всё нужное (файлы, заранее скачанные образы).\n" +
	"Для quiz: вопрос на понимание в goal, ответы студент пишет текстом в терминале.\n" +
	"Сложность честно по шкале 1-5. Ответ — только JSON строго по схеме:\n" +
	"{\n" +
	" \"id\": \"short-english-id\",\n" +
	" \"title\": \"Название по-русски\",\n" +
	" \"kind\": \"cmd\",\n" +
	" \"difficulty\": 3,\n" +
	" \"theory\": [\"абзац markdown\", \"ещё абзац с ```\\ncode block\\n```\"],\n" +
	" \"quiz\": [{\"question\": \"вопрос\", \"options\": [\"вариант1\", \"вариант2\", \"вариант3\"], \"correct\": 0}],\n" +
	" \"goal\": \"что сделать (или вопрос для quiz)\",\n" +
	" \"hints\": [\"подсказка 1\", \"подсказка 2\"],\n" +
	" \"check\": \"машиночитаемый критерий успеха по state\",\n" +
	" \"start_state\": {\"workdir\": \"/workspace\", \"files\": {}, \"images\": {}, \"containers\": {}, \"volumes\": {}, \"networks\": [\"bridge\", \"host\", \"none\"], \"events\": []}\n" +
	"}"

func (a *AIClient) GenerateTask(ctx context.Context, courseTitle, topic string, recent []string, style string) (*Task, error) {
	var user string
	if strings.HasPrefix(topic, "повторение") {
		user = fmt.Sprintf("Курс: %s\nТема: свободная — повторение уже пройденного материала курса (выбери подходящую тему сам, можно cmd или quiz).\nНедавние задачи (не повторять): %s\n", courseTitle, strings.Join(recent, "; "))
	} else {
		user = fmt.Sprintf("Курс: %s\nТема задачи (из программы или свободное описание студента): %s\nНедавние задачи (не повторять): %s\n", courseTitle, topic, strings.Join(recent, "; "))
	}
	if strings.TrimSpace(style) != "" {
		user += "\nОБЯЗАТЕЛЬНОЕ УКАЗАНИЕ СТУДЕНТА К СТИЛЮ И ФОРМАТУ (соблюдай строго):\n" + style + "\n"
	}
	user += "\nСгенерируй задачу по схеме. Ответ — только JSON."

	var t Task
	if err := a.chatJSON(ctx, sysTaskGen, user, &t, 0.6); err != nil {
		return nil, err
	}
	if strings.TrimSpace(t.Title) == "" || strings.TrimSpace(t.Goal) == "" {
		return nil, fmt.Errorf("модель вернула задачу без названия или условия")
	}
	if t.Kind != taskQuiz {
		t.Kind = taskCmd
	}
	if t.Difficulty < 1 || t.Difficulty > 5 {
		t.Difficulty = 3
	}
	if t.ID == "" {
		t.ID = "ai-" + fmt.Sprint(time.Now().Unix()%100000)
	}
	if len(t.Quiz) > 3 {
		t.Quiz = t.Quiz[:3]
	}
	for i := range t.Quiz {
		q := &t.Quiz[i]
		if len(q.Options) < 2 {
			q.Options = []string{"да", "нет"}
			q.Correct = 0
		}
		if q.Correct < 0 || q.Correct >= len(q.Options) {
			q.Correct = 0
		}
	}
	if len(t.Hints) == 0 {
		t.Hints = []string{"Перечитай условие и теорию.", "Спроси ментора в чате снизу."}
	}
	if len(t.Hints) > 2 {
		t.Hints = t.Hints[:2]
	}
	if t.Check == "" {
		t.Check = t.Goal
	}
	normalizeState(&t.Start)
	return &t, nil
}

// ---------- роль 5: генератор курсов по цели ----------

const sysCourseGen = "Ты — методист, собирающий учебную программу для тренажёра (терминальные симуляции: Docker/Linux/Git/сети/CI-CD). Пользователь описывает цель (например, «хочу девопс»).\n" +
	"Составь от 3 до 5 ПОСЛЕДОВАТЕЛЬНЫХ курсов от базы к цели. В каждом курсе syllabus — упорядоченный список тем (10-20 тем): формат каждой темы — \"cmd: ...\" для практики командами или \"quiz: ...\" для теста на понимание. Включай смежные темы, нужные для цели (для девопса: сети, Linux, Git, CI/CD, мониторинг).\n" +
	"Ответ — только JSON:\n" +
	"{\"courses\":[{\"id\":\"linux-basics\",\"title\":\"Краткое название\",\"desc\":\"одно предложение\",\"syllabus\":[\"cmd: ...\",\"quiz: ...\"]}]}"

type genCoursesResp struct {
	Courses []Course `json:"courses"`
}

func (a *AIClient) GenerateCourses(ctx context.Context, goal string) ([]Course, error) {
	user := "Цель студента: " + goal + "\n\nСобери программу. Ответ — только JSON."
	var resp genCoursesResp
	if err := a.chatJSON(ctx, sysCourseGen, user, &resp, 0.5); err != nil {
		return nil, err
	}
	if len(resp.Courses) == 0 {
		return nil, fmt.Errorf("модель не вернула ни одного курса")
	}
	now := time.Now().Unix()
	for i := range resp.Courses {
		c := &resp.Courses[i]
		if c.ID == "" {
			c.ID = fmt.Sprintf("ai-%d-%d", now%100000, i)
		} else {
			c.ID = "ai-" + c.ID
		}
		if c.Title == "" {
			c.Title = fmt.Sprintf("Курс %d", i+1)
		}
		if len(c.Syllabus) == 0 {
			c.Syllabus = []string{"cmd: вводная практика по теме курса"}
		}
	}
	return resp.Courses, nil
}

// ---------- общий механизм ----------

func (a *AIClient) chatJSON(ctx context.Context, system, user string, out any, temp float32) error {
	// Сначала просим строгий JSON. Не все провайдеры/модели поддерживают response_format —
	// тогда повторяем без него и вытаскиваем JSON из ответа сами.
	resp, err := a.cli.CreateChatCompletion(ctx, openai.ChatCompletionRequest{
		Model: a.model,
		Messages: []openai.ChatCompletionMessage{
			{Role: openai.ChatMessageRoleSystem, Content: system},
			{Role: openai.ChatMessageRoleUser, Content: user},
		},
		Temperature: temp,
		ResponseFormat: &openai.ChatCompletionResponseFormat{
			Type: "json_object",
		},
	})
	if err != nil {
		resp, err = a.cli.CreateChatCompletion(ctx, openai.ChatCompletionRequest{
			Model: a.model,
			Messages: []openai.ChatCompletionMessage{
				{Role: openai.ChatMessageRoleSystem, Content: system + "\nОтвечай ТОЛЬКО валидным JSON, без markdown и пояснений."},
				{Role: openai.ChatMessageRoleUser, Content: user},
			},
			Temperature: temp,
		})
		if err != nil {
			return err
		}
	}
	if len(resp.Choices) == 0 {
		return fmt.Errorf("пустой ответ модели")
	}
	content := cleanJSON(resp.Choices[0].Message.Content)
	if err := json.Unmarshal([]byte(content), out); err != nil {
		return fmt.Errorf("модель вернула не-JSON: %w", err)
	}
	return nil
}

func cleanJSON(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "```json")
	s = strings.TrimPrefix(s, "```")
	s = strings.TrimSuffix(s, "```")
	return strings.TrimSpace(s)
}
