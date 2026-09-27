// local.go — локальный fast-path команд (без ИИ), достижения,
// настраиваемые горячие клавиши и диктовка через whisper.cpp.
package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/driver/desktop"
	"fyne.io/fyne/v2/widget"
)

// ---------- FAST-PATH: read-only команды из состояния ----------

// tryLocalCommand — мгновенная локальная обработка команд без ИИ.
// Возвращает (обработано, вывод). Вывод печатается в терминал и пишется в историю
// вызывающей стороной (runCommand).
func (a *App) tryLocalCommand(raw string) (bool, string) {
	st := a.state()
	fields := strings.Fields(raw)
	if len(fields) == 0 {
		return false, ""
	}
	switch fields[0] {
	case "pwd":
		return true, st.Workdir
	case "echo":
		return true, strings.Join(fields[1:], " ")
	case "ls":
		prefix := ""
		if len(fields) > 1 {
			prefix = strings.Trim(fields[1], "/")
		}
		var names []string
		for n := range st.Files {
			if prefix == "" || strings.HasPrefix(n, prefix) {
				names = append(names, n)
			}
		}
		sort.Strings(names)
		return true, strings.Join(names, "   ")
	case "cat":
		if len(fields) < 2 {
			return true, "cat: missing operand"
		}
		if body, ok := st.Files[fields[1]]; ok {
			return true, body
		}
		return true, "cat: " + fields[1] + ": No such file or directory"
	case "cd":
		if len(fields) > 1 {
			target := fields[1]
			if !strings.HasPrefix(target, "/") {
				target = strings.TrimSuffix(st.Workdir, "/") + "/" + target
			}
			st.Workdir = filepath.Clean(target)
		} else {
			st.Workdir = "/"
		}
		a.states[a.stateKey()] = st
		return true, ""
	case "docker":
		handled, out := a.tryLocalDocker(fields[1:], &st)
		if handled {
			a.states[a.stateKey()] = st
		}
		return handled, out
	}
	return false, ""
}

func (a *App) tryLocalDocker(args []string, st *SandboxState) (bool, string) {
	if len(args) == 0 {
		return false, ""
	}
	switch args[0] {
	case "ps":
		all := len(args) > 1 && (args[1] == "-a" || args[1] == "--all")
		var b strings.Builder
		b.WriteString("CONTAINER ID   IMAGE                  STATUS         PORTS                    NAMES")
		names := make([]string, 0, len(st.Containers))
		for n := range st.Containers {
			names = append(names, n)
		}
		sort.Strings(names)
		for _, n := range names {
			c := st.Containers[n]
			if c == nil {
				continue
			}
			if !all && c.Status != "running" {
				continue
			}
			status := "Up"
			if c.Status != "running" {
				if c.Status == "exited" || strings.HasPrefix(c.Status, "exited") {
					status = "Exited"
				} else {
					status = "Exited (" + c.Status + ")"
				}
			}
			b.WriteString("\n" + fmt.Sprintf("%-14s %-22s %-14s %-24s %s", c.ID, c.Image, status, c.Ports, n))
		}
		return true, b.String()
	case "images":
		var b strings.Builder
		b.WriteString("REPOSITORY      TAG       IMAGE ID        SIZE")
		keys := make([]string, 0, len(st.Images))
		for k := range st.Images {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			img := st.Images[k]
			if img == nil {
				continue
			}
			id := strings.TrimPrefix(img.ID, "sha256:")
			b.WriteString("\n" + fmt.Sprintf("%-15s %-9s %-15s %dMB", img.Repo, img.Tag, "sha256:"+id, img.SizeMB))
		}
		return true, b.String()
	case "volume":
		if len(args) < 2 || args[1] != "ls" {
			return false, ""
		}
		var b strings.Builder
		b.WriteString("DRIVER   VOLUME NAME")
		vols := make([]string, 0, len(st.Volumes))
		for v := range st.Volumes {
			vols = append(vols, v)
		}
		sort.Strings(vols)
		for _, v := range vols {
			b.WriteString("\nlocal    " + v)
		}
		return true, b.String()
	case "network":
		if len(args) < 2 || args[1] != "ls" {
			return false, ""
		}
		var b strings.Builder
		b.WriteString("NETWORK ID     NAME     DRIVER")
		for _, n := range st.Networks {
			driver := n
			if n == "none" {
				driver = "null"
			}
			b.WriteString("\n" + fmt.Sprintf("%-14s %-8s %s", fakeID("net:"+n), n, driver))
		}
		return true, b.String()
	case "rm":
		return localDockerRM(args[1:], st)
	case "stop":
		return localDockerLifecycle(args[1:], st, "stop", "exited")
	case "start":
		return localDockerLifecycle(args[1:], st, "start", "running")
	case "restart":
		return localDockerLifecycle(args[1:], st, "restart", "running")
	case "rmi":
		return localDockerRMI(args[1:], st)
	}
	return false, ""
}

func findContainerName(st *SandboxState, ref string) string {
	if c, ok := st.Containers[ref]; ok && c != nil {
		return ref
	}
	for n, c := range st.Containers {
		if c != nil && c.ID == ref {
			return n
		}
	}
	return ""
}

func localDockerRM(args []string, st *SandboxState) (bool, string) {
	force := false
	var targets []string
	for _, x := range args {
		switch x {
		case "-f", "--force":
			force = true
		default:
			targets = append(targets, x)
		}
	}
	if len(targets) == 0 {
		return true, "\"docker rm\" requires at least 1 argument."
	}
	var out []string
	for _, t := range targets {
		name := findContainerName(st, t)
		if name == "" {
			out = append(out, "Error response from daemon: No such container: "+t)
			continue
		}
		if st.Containers[name].Status == "running" && !force {
			out = append(out, "Error response from daemon: You cannot remove a running container "+name+". Stop the container before attempting removal or force remove")
			continue
		}
		delete(st.Containers, name)
		out = append(out, name)
	}
	return true, strings.Join(out, "\n")
}

func localDockerLifecycle(args []string, st *SandboxState, cmd, status string) (bool, string) {
	if len(args) == 0 {
		return true, fmt.Sprintf("\"docker %s\" requires at least 1 argument.", cmd)
	}
	var out []string
	for _, t := range args {
		name := findContainerName(st, t)
		if name == "" {
			out = append(out, "Error response from daemon: No such container: "+t)
			continue
		}
		st.Containers[name].Status = status
		out = append(out, name)
	}
	return true, strings.Join(out, "\n")
}

func findImageKey(st *SandboxState, ref string) string {
	if img, ok := st.Images[ref]; ok && img != nil {
		return ref
	}
	for k, img := range st.Images {
		if img == nil {
			continue
		}
		if img.ID == ref || strings.HasPrefix(img.ID, ref) {
			return k
		}
		if img.Repo+":"+img.Tag == ref || img.Repo == ref {
			return k
		}
	}
	return ""
}

func localDockerRMI(args []string, st *SandboxState) (bool, string) {
	if len(args) == 0 {
		return true, "\"docker rmi\" requires at least 1 argument."
	}
	var out []string
	for _, t := range args {
		key := findImageKey(st, t)
		if key == "" {
			out = append(out, "Error response from daemon: No such image: "+t)
			continue
		}
		delete(st.Images, key)
		out = append(out, "Untagged: "+t)
	}
	return true, strings.Join(out, "\n")
}

// ---------- ДОСТИЖЕНИЯ ----------

type Achievement struct {
	ID, Title, Desc string
}

var achievementList = []Achievement{
	{"first", "Первый шаг", "Решена первая задача"},
	{"ten", "Десятка", "10 решённых задач"},
	{"fifty", "Полсотни", "50 решённых задач"},
	{"docker-grad", "Выпускник Docker", "Все 15 встроенных задач курса Docker"},
	{"polyglot", "Полиглот", "Задачи решены в трёх курсах"},
	{"lvl5", "Уровень 5", "Достигнут пятый уровень"},
	{"lvl10", "Уровень 10", "Достигнут десятый уровень"},
	{"hard5", "Тяжеловес", "Решена задача сложности 5"},
	{"quiz-perfect", "Перфекционист", "Тест пройден с первой попытки"},
	{"author", "Сценарист", "Создана своя задача через ИИ"},
	{"architect", "Архитектор", "Собран свой курс через ИИ"},
	{"rebuilder", "Второй шанс", "Курс пересобран под свой стиль"},
	{"exam-good", "Аттестован", "Экзамен сдан на 4 или выше"},
	{"exam-perfect", "Отличник", "Экзамен сдан на 5"},
	{"streak3", "Серия 3", "3 дня подряд"},
	{"streak7", "Неделя огня", "7 дней подряд"},
	{"streak30", "Месяц дисциплины", "30 дней подряд"},
	{"review1", "Мнемоник", "Первый успешный повтор по закладке"},
}

func findAchievement(id string) *Achievement {
	for i := range achievementList {
		if achievementList[i].ID == id {
			return &achievementList[i]
		}
	}
	return nil
}

func (a *App) grant(id string) {
	if a.prog.Achieved == nil {
		a.prog.Achieved = map[string]string{}
	}
	if _, ok := a.prog.Achieved[id]; ok {
		return
	}
	meta := findAchievement(id)
	if meta == nil {
		return
	}
	a.prog.Achieved[id] = todayStr()
	a.saveProgress()
	a.termLine("  ★ достижение: «" + meta.Title + "» — " + meta.Desc)
	a.refreshTerminal()
	a.fyneApp.SendNotification(fyne.NewNotification("TERMAI", "Достижение: "+meta.Title))
}

func (a *App) checkProgressAchievements() {
	p := a.prog
	if p.SolvedTotal >= 1 {
		a.grant("first")
	}
	if p.SolvedTotal >= 10 {
		a.grant("ten")
	}
	if p.SolvedTotal >= 50 {
		a.grant("fifty")
	}
	if done := p.Completed["docker"]; done != nil {
		n := 0
		for _, t := range builtinTasks() {
			if done[t.ID] {
				n++
			}
		}
		if n >= 15 {
			a.grant("docker-grad")
		}
	}
	coursesWithSolved := 0
	for _, m := range p.Completed {
		for _, v := range m {
			if v {
				coursesWithSolved++
				break
			}
		}
	}
	if coursesWithSolved >= 3 {
		a.grant("polyglot")
	}
	if lvl := p.XP/100 + 1; lvl >= 5 {
		a.grant("lvl5")
	}
	if lvl := p.XP/100 + 1; lvl >= 10 {
		a.grant("lvl10")
	}
	if p.Streak >= 3 {
		a.grant("streak3")
	}
	if p.Streak >= 7 {
		a.grant("streak7")
	}
	if p.Streak >= 30 {
		a.grant("streak30")
	}
}

func achievementLines(p *Progress) []string {
	out := make([]string, 0, len(achievementList))
	for _, ach := range achievementList {
		if date, ok := p.Achieved[ach.ID]; ok && date != "" {
			out = append(out, "✓ "+ach.Title+" — "+ach.Desc+" ("+date+")")
		} else {
			out = append(out, "○ "+ach.Title+" — "+ach.Desc)
		}
	}
	return out
}

// ---------- ГОРЯЧИЕ КЛАВИШИ ----------

type hotkeyDef struct{ Action, Title, Default string }

var hotkeyDefs = []hotkeyDef{
	{"clear", "Очистить терминал", "Ctrl+L"},
	{"finish", "Завершить задачу", "Ctrl+Enter"},
	{"chat", "Фокус в чат ментора", "Ctrl+K"},
	{"term", "Фокус в терминал", "Ctrl+T"},
	{"toggle", "Теория ⇄ Терминал", "Ctrl+/"},
	{"newtask", "Новая задача от ИИ", "Ctrl+N"},
	{"review", "Закладки/Повторение", "Ctrl+R"},
	{"stats", "Статистика", "Ctrl+I"},
	{"files", "Файлы песочницы", "Ctrl+F"},
}

func (a *App) hotkeyFor(action string) string {
	if s, ok := a.cfg.Hotkeys[action]; ok && s != "" {
		return s
	}
	for _, d := range hotkeyDefs {
		if d.Action == action {
			return d.Default
		}
	}
	return ""
}

func (a *App) setupHotkeys() {
	if a.mobile {
		return
	}
	for _, d := range hotkeyDefs {
		combo := a.hotkeyFor(d.Action)
		if sc, ok := parseCombo(combo); ok {
			act := d.Action
			a.win.Canvas().AddShortcut(sc, func(fyne.Shortcut) { a.runHotkey(act) })
		}
	}
}

// registerShortcut — вызывается при назначении новой комбинации «на лету».
// Старая комбинация продолжит срабатывать до перезапуска.
func (a *App) registerShortcut(action, combo string) {
	if sc, ok := parseCombo(combo); ok {
		act := action
		a.win.Canvas().AddShortcut(sc, func(fyne.Shortcut) { a.runHotkey(act) })
	}
}

func (a *App) runHotkey(action string) {
	if a.capturing != "" {
		return
	}
	switch action {
	case "clear":
		a.termText = ""
		a.termLine("  (вывод терминала очищен)")
		a.refreshTerminal()
	case "finish":
		a.onFinishTask()
	case "chat":
		a.win.Canvas().Focus(a.chatIn)
	case "term":
		a.switchTab("terminal")
	case "toggle":
		if a.tab == "theory" {
			a.switchTab("terminal")
		} else {
			a.switchTab("theory")
		}
	case "newtask":
		a.openTaskDialog()
	case "review":
		a.showReview()
	case "stats":
		a.showStats()
	case "files":
		a.showFiles()
	}
}

func parseCombo(s string) (fyne.Shortcut, bool) {
	parts := strings.Split(s, "+")
	if len(parts) == 0 || parts[len(parts)-1] == "" {
		return nil, false
	}
	key := parts[len(parts)-1]
	mod := fyne.KeyModifier(0)
	for _, p := range parts[:len(parts)-1] {
		switch p {
		case "Ctrl":
			mod |= fyne.KeyModifierControl
		case "Shift":
			mod |= fyne.KeyModifierShift
		case "Alt":
			mod |= fyne.KeyModifierAlt
		case "Super":
			mod |= fyne.KeyModifierSuper
		default:
			return nil, false
		}
	}
	kn := normalizeKeyName(key)
	if kn == "" {
		return nil, false
	}
	return &desktop.CustomShortcut{KeyName: kn, Modifier: mod}, true
}

func normalizeKeyName(s string) fyne.KeyName {
	switch s {
	case "Enter":
		return fyne.KeyReturn
	case "Esc", "Escape":
		return fyne.KeyEscape
	case "Space":
		return fyne.KeySpace
	case "Tab":
		return fyne.KeyTab
	case "Up":
		return fyne.KeyUp
	case "Down":
		return fyne.KeyDown
	case "Left":
		return fyne.KeyLeft
	case "Right":
		return fyne.KeyRight
	case "/":
		return fyne.KeySlash
	case ",":
		return fyne.KeyComma
	case ".":
		return fyne.KeyPeriod
	case "-":
		return fyne.KeyMinus
	case "=":
		return fyne.KeyEqual
	case "[":
		return fyne.KeyLeftBracket
	case "]":
		return fyne.KeyRightBracket
	case ";":
		return fyne.KeySemicolon
	case "'":
		return fyne.KeyApostrophe
	case "\\":
		return fyne.KeyBackslash
	case "`":
		return fyne.KeyBackTick
	}
	if len(s) == 1 {
		return fyne.KeyName(strings.ToUpper(s))
	}
	return fyne.KeyName(s)
}

func displayKeyName(k fyne.KeyName) string {
	switch k {
	case fyne.KeyReturn:
		return "Enter"
	case fyne.KeyEscape:
		return "Esc"
	case fyne.KeySlash:
		return "/"
	case fyne.KeyComma:
		return ","
	case fyne.KeyPeriod:
		return "."
	case fyne.KeyMinus:
		return "-"
	case fyne.KeyEqual:
		return "="
	case fyne.KeyLeftBracket:
		return "["
	case fyne.KeyRightBracket:
		return "]"
	case fyne.KeySemicolon:
		return ";"
	case fyne.KeyApostrophe:
		return "'"
	case fyne.KeyBackslash:
		return "\\"
	case fyne.KeyBackTick:
		return "`"
	}
	return string(k)
}

func comboFromCS(cs *desktop.CustomShortcut) string {
	var parts []string
	m := cs.Modifier
	if m&fyne.KeyModifierControl != 0 {
		parts = append(parts, "Ctrl")
	}
	if m&fyne.KeyModifierShift != 0 {
		parts = append(parts, "Shift")
	}
	if m&fyne.KeyModifierAlt != 0 {
		parts = append(parts, "Alt")
	}
	if m&fyne.KeyModifierSuper != 0 {
		parts = append(parts, "Super")
	}
	parts = append(parts, displayKeyName(cs.KeyName))
	return strings.Join(parts, "+")
}

func isFKeyName(n string) bool {
	if len(n) < 2 || n[0] != 'F' {
		return false
	}
	for _, r := range n[1:] {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// captureEntry — поле для захвата комбинации в диалоге настроек.
type captureEntry struct {
	widget.Entry
	onCombo func(*desktop.CustomShortcut)
	onKey   func(*fyne.KeyEvent)
}

func (c *captureEntry) TypedShortcut(s fyne.Shortcut) {
	if cs, ok := s.(*desktop.CustomShortcut); ok && c.onCombo != nil {
		c.onCombo(cs)
	}
}

func (c *captureEntry) TypedKey(e *fyne.KeyEvent) {
	if c.onKey != nil {
		c.onKey(e)
	}
}

func (a *App) hotkeyConflict(action, combo string) string {
	for _, def := range hotkeyDefs {
		if def.Action == action {
			continue
		}
		if a.hotkeyFor(def.Action) == combo {
			return def.Title
		}
	}
	return ""
}

func (a *App) captureHotkey(action string, btn *widget.Button) {
	if a.capturing != "" {
		return
	}
	ce := &captureEntry{}
	ce.PlaceHolder = "нажми комбинацию…"
	done := false
	var d dialog.Dialog

	apply := func(combo string) {
		if a.cfg.Hotkeys == nil {
			a.cfg.Hotkeys = map[string]string{}
		}
		a.cfg.Hotkeys[action] = combo
		_ = saveConfig(a.cfg)
		if other := a.hotkeyConflict(action, combo); other != "" {
			dialog.ShowInformation("Конфликт", "Эта комбинация уже занята действием: "+other+". Она будет срабатывать и там, и там до перезапуска — выбери другую.", a.win)
		}
		btn.SetText(combo)
		btn.Refresh()
		a.registerShortcut(action, combo)
	}

	ce.onCombo = func(cs *desktop.CustomShortcut) {
		if done {
			return
		}
		done = true
		a.capturing = ""
		apply(comboFromCS(cs))
		d.Hide()
	}
	ce.onKey = func(e *fyne.KeyEvent) {
		if done {
			return
		}
		switch {
		case e.Name == fyne.KeyEscape:
			done = true
			a.capturing = ""
			d.Hide()
		case isFKeyName(string(e.Name)):
			done = true
			a.capturing = ""
			apply(string(e.Name))
			d.Hide()
		}
	}

	content := container.NewVBox(
		wlabel("Нажми желаемую комбинацию: Ctrl/Alt/Shift + клавишу\nили F-клавиша. Esc — отмена."),
		spacerVM(8),
		ce,
	)
	d = dialog.NewCustomConfirm("Назначить клавиши", "Готово", "Отмена", content, func(ok bool) {
		if !done {
			a.capturing = ""
		}
	}, a.win)
	a.resizeDialog(d, 440, 200)
	d.Show()
	a.win.Canvas().Focus(ce)
	a.capturing = action
}

func spacerVM(h float32) fyne.CanvasObject {
	return container.NewGridWrap(fyne.NewSize(1, h), canvas.NewRectangle(colClear))
}

// ---------- ДИКТОВКА (whisper.cpp, локально; запись — Linux) ----------

// whisperStatus — служебные сообщения диктовки. Пишем их в терминал, а не в чат ментора,
// чтобы не засорять диалог.
func (a *App) whisperStatus(text string) {
	a.termLine("  [микрофон] " + text)
	a.refreshTerminal()
}

func (a *App) onMicTap() {
	if a.recProc != nil {
		a.stopRecording()
		return
	}
	if a.micBusy {
		return
	}
	a.startRecording()
}

func findRecorder() (string, []string) {
	if p, err := exec.LookPath("parecord"); err == nil {
		return p, []string{"--format=s16le", "--rate=16000", "--channels=1", "--file-format=wav"}
	}
	if p, err := exec.LookPath("arecord"); err == nil {
		return p, []string{"-f", "S16_LE", "-r", "16000", "-c", "1", "-d", "60"}
	}
	return "", nil
}

func exeDir() string {
	exe, err := os.Executable()
	if err != nil {
		if wd, e := os.Getwd(); e == nil {
			return wd
		}
		return "."
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	return filepath.Dir(exe)
}

func (a *App) resolveWhisperBin() string {
	if a.cfg.WhisperBin != "" {
		if _, err := os.Stat(a.cfg.WhisperBin); err == nil {
			return a.cfg.WhisperBin
		}
	}
	// 1) рядом с приложением (поставляется в комплекте)
	root := exeDir()
	for _, p := range []string{
		filepath.Join(root, "whisper-cli"),
		filepath.Join(root, "bin", "whisper-cli"),
		filepath.Join(root, "whisper.cpp", "build", "bin", "whisper-cli"),
		filepath.Join(root, "whisper-cpp", "whisper-cli"),
	} {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	// 2) в PATH
	if p, err := exec.LookPath("whisper-cli"); err == nil {
		return p
	}
	// 3) домашние сборки / системные
	home, _ := os.UserHomeDir()
	for _, p := range []string{
		filepath.Join(home, "whisper.cpp", "build", "bin", "whisper-cli"),
		"/usr/local/bin/whisper-cli",
	} {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func (a *App) resolveWhisperModel() string {
	if a.cfg.WhisperModel != "" {
		if _, err := os.Stat(a.cfg.WhisperModel); err == nil {
			return a.cfg.WhisperModel
		}
	}
	names := []string{"ggml-base.bin", "ggml-small.bin", "ggml-tiny.bin"}
	// 1) рядом с приложением (поставляется в комплекте)
	root := exeDir()
	for _, name := range names {
		for _, p := range []string{
			filepath.Join(root, name),
			filepath.Join(root, "models", name),
			filepath.Join(root, "whisper.cpp", name),
		} {
			if _, err := os.Stat(p); err == nil {
				return p
			}
		}
	}
	// 2) папка конфигурации
	if dir, err := os.UserConfigDir(); err == nil {
		for _, name := range names {
			p := filepath.Join(dir, "termai", name)
			if _, err := os.Stat(p); err == nil {
				return p
			}
		}
	}
	// 3) текущая рабочая папка
	if wd, err := os.Getwd(); err == nil {
		for _, name := range names {
			p := filepath.Join(wd, name)
			if _, err := os.Stat(p); err == nil {
				return p
			}
		}
	}
	return ""
}

func (a *App) whisperSetupDialog() {
	content := container.NewVBox(
		wlabel("Для диктовки нужен whisper.cpp (локально, без интернета).\nЗапись звука пока поддерживается на Linux (parecord/arecord)."),
		spacerVM(8),
		wlabel("1) Собери whisper-cli:\n"+
			"   git clone https://github.com/ggml-org/whisper.cpp\n"+
			"   cd whisper.cpp && cmake -B build && cmake --build build -j\n"+
			"   бинарник: build/bin/whisper-cli"),
		wlabel("2) В настройках TERMAI нажми «Скачать модель ggml-base» (~148 МБ)\n    или укажи пути к whisper-cli и модели вручную.\n    Для большей точности возьми ggml-small.bin."),
	)
	d := dialog.NewCustom("Диктовка: настройка", "Понятно", content, a.win)
	a.resizeDialog(d, 580, 340)
	d.Show()
}

func (a *App) startRecording() {
	recPath, base := findRecorder()
	if recPath == "" {
		a.whisperSetupDialog()
		return
	}
	if a.resolveWhisperBin() == "" || a.resolveWhisperModel() == "" {
		a.whisperSetupDialog()
		return
	}
	tmp := filepath.Join(os.TempDir(), fmt.Sprintf("termai-%d.wav", time.Now().UnixNano()))
	cmd := exec.Command(recPath, append(base, tmp)...)
	if err := cmd.Start(); err != nil {
		a.mentorSay("system", "Не удалось начать запись: "+err.Error())
		return
	}
	a.recProc = cmd
	a.recFile = tmp
	a.micBtn.SetText("■ Стоп")
	a.micBtn.Importance = widget.DangerImportance
	a.micBtn.Refresh()
	a.whisperStatus("Запись пошла — нажми «Стоп», чтобы распознать.")
}

func (a *App) stopRecording() {
	cmd := a.recProc
	file := a.recFile
	a.recProc = nil
	a.recFile = ""
	a.micBtn.SetText("Диктовать")
	a.micBtn.Importance = widget.MediumImportance
	a.micBtn.Refresh()
	if cmd == nil {
		return
	}
	_ = cmd.Process.Signal(os.Interrupt) // parecord/arecord корректно закрывают WAV по SIGINT
	done := make(chan struct{})
	go func() {
		_ = cmd.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		_ = cmd.Process.Kill()
		<-done
	}
	go a.transcribe(file)
}

func whisperText(out string) string {
	var lines []string
	for _, ln := range strings.Split(out, "\n") {
		t := strings.TrimSpace(ln)
		if t == "" {
			continue
		}
		// отбрасываем служебный вывод/логи whisper, оставляя только распознанный текст
		if strings.HasPrefix(t, "[") || strings.Contains(t, "-->") {
			continue
		}
		if strings.HasPrefix(t, "whisper_") || strings.HasPrefix(t, "read_audio_data") ||
			strings.HasPrefix(t, "main:") || strings.HasPrefix(t, "system_info") ||
			strings.Contains(t, "trying to decode with") || strings.Contains(t, "reading audio data from") {
			continue
		}
		lines = append(lines, t)
	}
	return strings.Join(lines, " ")
}

// isWhisperHallucination — типичные «фантомные» фразы whisper на тишине/шуме.
// Их нельзя вставлять в поле ввода как реальную речь.
func isWhisperHallucination(text string) bool {
	t := strings.ToLower(strings.TrimSpace(text))
	if t == "" {
		return true
	}
	for _, frag := range []string{
		"редактор субтитров", "корректор", "субтитры", "dimatorzok", "продолжение следует",
		"спасибо за просмотр", "подписывайтесь", "ставьте лайк", "мы в telegram",
	} {
		if strings.Contains(t, frag) {
			return true
		}
	}
	// очень короткие обрубки из одной-двух букв
	if len([]rune(t)) <= 2 {
		return true
	}
	return false
}

func (a *App) transcribe(path string) {
	a.micBusy = true
	fyne.Do(func() { a.micBtn.Disable() })
	defer func() {
		_ = os.Remove(path)
		a.micBusy = false
		fyne.Do(func() { a.micBtn.Enable() })
	}()

	bin := a.resolveWhisperBin()
	model := a.resolveWhisperModel()
	if bin == "" || model == "" {
		fyne.Do(func() { a.whisperSetupDialog() })
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
	defer cancel()
	// stdout — только распознанный текст; логи whisper идут в stderr и не должны попадать в чат
	cmd := exec.CommandContext(ctx, bin, "-m", model, "-f", path, "-l", "ru", "-nt", "-np")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		if len(msg) > 300 {
			msg = msg[:300]
		}
		fyne.Do(func() {
			a.whisperStatus("Ошибка whisper: " + msg + ". Проверь пути в настройках.")
		})
		return
	}
	text := whisperText(string(out))
	if isWhisperHallucination(text) {
		fyne.Do(func() {
			a.whisperStatus("Не расслышал — попробуй ещё раз, говори чуть ближе к микрофону.")
		})
		return
	}
	fyne.Do(func() {
		existing := strings.TrimSpace(a.chatIn.Text)
		if existing == "" {
			a.chatIn.SetText(text)
		} else {
			a.chatIn.SetText(existing + " " + text)
		}
		a.win.Canvas().Focus(a.chatIn)
		a.whisperStatus("Распознано — проверь текст перед отправкой.")
	})
}

func (a *App) downloadWhisperModel(entry *widget.Entry) {
	dir, err := os.UserConfigDir()
	if err != nil {
		a.mentorSay("system", "Не удалось определить папку конфигурации: "+err.Error())
		return
	}
	target := filepath.Join(dir, "termai", "ggml-base.bin")
	if _, err := os.Stat(target); err == nil {
		a.cfg.WhisperModel = target
		_ = saveConfig(a.cfg)
		entry.SetText(target)
		dialog.ShowInformation("Модель", "Уже скачана: "+target, a.win)
		return
	}
	_ = os.MkdirAll(filepath.Dir(target), 0o755)
	tmp := target + ".part"
	a.whisperStatus("Скачиваю модель ggml-base (~148 МБ)… это пару минут.")
	go func() {
		var cmd *exec.Cmd
		if _, err := exec.LookPath("wget"); err == nil {
			cmd = exec.Command("wget", "-q", "-O", tmp,
				"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")
		} else if _, err := exec.LookPath("curl"); err == nil {
			cmd = exec.Command("curl", "-sL", "-o", tmp,
				"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")
		} else {
			fyne.Do(func() { a.whisperStatus("Для скачивания нужен wget или curl.") })
			return
		}
		err := cmd.Run()
		fyne.Do(func() {
			if err != nil {
				a.whisperStatus("Скачивание не удалось: " + err.Error())
				return
			}
			if err := os.Rename(tmp, target); err != nil {
				a.whisperStatus("Не удалось сохранить модель: " + err.Error())
				return
			}
			a.cfg.WhisperModel = target
			_ = saveConfig(a.cfg)
			entry.SetText(target)
			a.whisperStatus("Модель готова: " + target)
		})
	}()
}
