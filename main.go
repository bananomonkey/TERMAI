// main.go — TERMAI: окно, тема, layout и логика UI мультикурсового тренажёра.
package main

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image/color"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/driver/desktop"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"

	_ "modernc.org/sqlite"
)

// ---------- палитра и тема ----------

const (
	colNamePanel   fyne.ThemeColorName = "dtPanel"
	colNameMuted   fyne.ThemeColorName = "dtMuted"
	colNameSection fyne.ThemeColorName = "dtSection"
	colNameBorder  fyne.ThemeColorName = "dtBorder"
)

var (
	colFg     = color.NRGBA{R: 0xe8, G: 0xe6, B: 0xe3, A: 0xff}
	colAccent = color.NRGBA{R: 0xd9, G: 0x77, B: 0x57, A: 0xff}
	colMuted  = color.NRGBA{R: 0x9a, G: 0x93, B: 0x8c, A: 0xff}
	colPanel  = color.NRGBA{R: 0x20, G: 0x1f, B: 0x1e, A: 0xff}
	colTerm   = color.NRGBA{R: 0x0f, G: 0x0f, B: 0x0f, A: 0xff}
	colClear  = color.NRGBA{A: 0}
	colGood   = color.NRGBA{R: 0x84, G: 0xa8, B: 0x73, A: 0xff}
	colWarn   = color.NRGBA{R: 0xd9, G: 0xa0, B: 0x5b, A: 0xff}
)

type claudeTheme struct {
	fyne.Theme
	fontRegular fyne.Resource
	fontBold    fyne.Resource
}

func newClaudeTheme(fontPath string) *claudeTheme {
	reg, bold := findFonts(fontPath)
	return &claudeTheme{Theme: theme.DarkTheme(), fontRegular: reg, fontBold: bold}
}

func nrgba(v uint32) color.Color {
	return color.NRGBA{R: uint8(v >> 16), G: uint8(v >> 8), B: uint8(v), A: 0xff}
}

func (t *claudeTheme) Color(name fyne.ThemeColorName, variant fyne.ThemeVariant) color.Color {
	switch name {
	case theme.ColorNameBackground:
		return nrgba(0x1a1a1a)
	case theme.ColorNameForeground:
		return nrgba(0xe8e6e3)
	case theme.ColorNamePrimary:
		return nrgba(0xd97757)
	case theme.ColorNameButton:
		return nrgba(0x2e2e2e)
	case theme.ColorNameInputBackground:
		return nrgba(0x0f0f0f)
	case theme.ColorNameInputBorder:
		return nrgba(0x3a3835)
	case theme.ColorNameMenuBackground:
		return nrgba(0x232120)
	case theme.ColorNameOverlayBackground:
		return nrgba(0x232120)
	case theme.ColorNameHover:
		return nrgba(0x3a3835)
	case theme.ColorNamePressed:
		return nrgba(0x454140)
	case theme.ColorNameFocus:
		return color.NRGBA{R: 0xd9, G: 0x77, B: 0x57, A: 0x60}
	case theme.ColorNameSelection:
		return nrgba(0x453430)
	case theme.ColorNameSeparator:
		return nrgba(0x2c2b29)
	case theme.ColorNamePlaceHolder:
		return nrgba(0x77716b)
	case theme.ColorNameDisabled:
		return nrgba(0x2a2927)
	case theme.ColorNameDisabledButton:
		return nrgba(0x242322)
	case theme.ColorNameShadow:
		return color.NRGBA{A: 0}
	case theme.ColorNameSuccess:
		return nrgba(0x84a873)
	case theme.ColorNameWarning:
		return nrgba(0xd9a05b)
	case theme.ColorNameError:
		return nrgba(0xcf6a5a)
	case theme.ColorNameScrollBar:
		return nrgba(0x3a3835)
	case colNamePanel:
		return nrgba(0x201f1e)
	case colNameMuted:
		return nrgba(0x9a938c)
	case colNameSection:
		return nrgba(0x252423)
	case colNameBorder:
		return nrgba(0x2c2b29)
	}
	return t.Theme.Color(name, variant)
}

func (t *claudeTheme) Size(name fyne.ThemeSizeName) float32 {
	switch name {
	case theme.SizeNameText:
		return 14
	case theme.SizeNameHeadingText:
		return 18
	case theme.SizeNameSubHeadingText:
		return 14
	case theme.SizeNameCaptionText:
		return 12
	case theme.SizeNamePadding:
		return 8
	case theme.SizeNameLineSpacing:
		return 4
	case theme.SizeNameScrollBar:
		return 10
	}
	return t.Theme.Size(name)
}

func (t *claudeTheme) Font(style fyne.TextStyle) fyne.Resource {
	if style.Monospace {
		return t.Theme.Font(style)
	}
	if style.Bold && t.fontBold != nil {
		return t.fontBold
	}
	if t.fontRegular != nil {
		return t.fontRegular
	}
	return t.Theme.Font(style)
}

// ---------- поиск шрифта ----------

func findFonts(fontPath string) (fyne.Resource, fyne.Resource) {
	regPath, boldPath := "", ""
	if fontPath != "" {
		regPath = fontPath
		boldPath = boldSibling(fontPath)
	} else {
		regPath, boldPath = locateTiempos()
	}
	toRes := func(p string) fyne.Resource {
		if p == "" {
			return nil
		}
		data, err := os.ReadFile(p)
		if err != nil {
			return nil
		}
		return fyne.NewStaticResource(filepath.Base(p), data)
	}
	return toRes(regPath), toRes(boldPath)
}

func locateTiempos() (reg, bold string) {
	for _, dir := range fontDirs() {
		_ = filepath.WalkDir(dir, func(p string, d os.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if d.IsDir() {
				if p != dir && depthBelow(dir, p) > 2 {
					return filepath.SkipDir
				}
				return nil
			}
			low := strings.ToLower(p)
			if !strings.HasSuffix(low, ".ttf") && !strings.HasSuffix(low, ".otf") {
				return nil
			}
			if !strings.Contains(low, "tiempos") || strings.Contains(low, "italic") {
				return nil
			}
			isBold := strings.Contains(low, "bold") || strings.Contains(low, "semibold")
			if isBold && bold == "" {
				bold = p
			}
			if !isBold && reg == "" {
				reg = p
			}
			return nil
		})
		if reg != "" {
			return reg, bold
		}
	}
	return "", ""
}

func depthBelow(root, p string) int {
	rel, err := filepath.Rel(root, p)
	if err != nil {
		return 99
	}
	return strings.Count(rel, string(filepath.Separator))
}

func fontDirs() []string {
	home, _ := os.UserHomeDir()
	switch runtime.GOOS {
	case "darwin":
		return []string{filepath.Join(home, "Library", "Fonts"), "/Library/Fonts", "/System/Library/Fonts"}
	case "windows":
		return []string{filepath.Join(os.Getenv("WINDIR"), "Fonts")}
	default:
		return []string{filepath.Join(home, ".local", "share", "fonts"), filepath.Join(home, ".fonts"), "/usr/share/fonts"}
	}
}

func boldSibling(path string) string {
	dir, name := filepath.Split(path)
	ext := filepath.Ext(name)
	base := strings.TrimSuffix(name, ext)
	for _, c := range []string{
		base + "-Bold" + ext,
		base + "_Bold" + ext,
		base + "Bold" + ext,
		strings.Replace(base, "Regular", "Bold", 1) + ext,
		strings.Replace(base, "Regular", "Semibold", 1) + ext,
	} {
		p := filepath.Join(dir, c)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

// ---------- конфиг и прогресс ----------

type Config struct {
	APIKey       string            `json:"api_key"`
	Provider     string            `json:"provider,omitempty"`
	Model        string            `json:"model,omitempty"`
	BaseURL      string            `json:"base_url,omitempty"`
	FontPath     string            `json:"font_path,omitempty"`
	Hotkeys      map[string]string `json:"hotkeys,omitempty"`
	WhisperBin   string            `json:"whisper_bin,omitempty"`
	WhisperModel string            `json:"whisper_model,omitempty"`
}

func dataDir() string {
	if app := fyne.CurrentApp(); app != nil && fyne.CurrentDevice().IsMobile() {
		if u := app.Storage().RootURI(); u != nil {
			if p := u.Path(); p != "" {
				return p
			}
		}
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = "."
	}
	return dir
}

func configPath() string {
	return filepath.Join(dataDir(), "docker-trainer.json")
}

func loadConfig() *Config {
	c := &Config{}
	if data, err := os.ReadFile(configPath()); err == nil {
		_ = json.Unmarshal(data, c)
	}
	if c.Hotkeys == nil {
		c.Hotkeys = map[string]string{}
	}
	return c
}

func saveConfig(c *Config) error {
	data, _ := json.MarshalIndent(c, "", "  ")
	return os.WriteFile(configPath(), data, 0o600)
}

type Bookmark struct {
	TaskID   string      `json:"task_id"`
	CourseID string      `json:"course_id"`
	Interval int         `json:"interval_days"`
	Due      string      `json:"due"`
	History  []HistEntry `json:"history,omitempty"`
}

type Progress struct {
	XP          int                        `json:"xp"`
	LastCourse  string                     `json:"last_course,omitempty"`
	SolvedTotal int                        `json:"solved_total"`
	Streak      int                        `json:"streak"`
	LastDay     string                     `json:"last_day"`
	Completed   map[string]map[string]bool `json:"completed"`
	Hints       map[string]map[string]int  `json:"hints"`
	Generated   map[string][]Task          `json:"generated"`
	Extra       []Course                   `json:"extra_courses,omitempty"`
	DiffCount   map[string]int             `json:"difficulty_solved"`
	Bookmarks   map[string]*Bookmark       `json:"bookmarks"`
	QuizDone    map[string]map[string]bool `json:"quiz_done"`
	QuizTries   map[string]map[string]int  `json:"quiz_tries"`
	Overrides   map[string]map[int]Task    `json:"task_overrides"`
	Achieved    map[string]string          `json:"achievements"`
	TimeSeconds map[string]int             `json:"time_seconds"`
}

func newProgress() *Progress {
	return &Progress{
		Completed:   map[string]map[string]bool{},
		Hints:       map[string]map[string]int{},
		Generated:   map[string][]Task{},
		DiffCount:   map[string]int{},
		Bookmarks:   map[string]*Bookmark{},
		QuizDone:    map[string]map[string]bool{},
		QuizTries:   map[string]map[string]int{},
		Overrides:   map[string]map[int]Task{},
		Achieved:    map[string]string{},
		TimeSeconds: map[string]int{},
	}
}

func (p *Progress) ensure() {
	if p.Completed == nil {
		p.Completed = map[string]map[string]bool{}
	}
	if p.Hints == nil {
		p.Hints = map[string]map[string]int{}
	}
	if p.Generated == nil {
		p.Generated = map[string][]Task{}
	}
	if p.DiffCount == nil {
		p.DiffCount = map[string]int{}
	}
	if p.Bookmarks == nil {
		p.Bookmarks = map[string]*Bookmark{}
	}
	if p.QuizDone == nil {
		p.QuizDone = map[string]map[string]bool{}
	}
	if p.QuizTries == nil {
		p.QuizTries = map[string]map[string]int{}
	}
	if p.Overrides == nil {
		p.Overrides = map[string]map[int]Task{}
	}
	if p.Achieved == nil {
		p.Achieved = map[string]string{}
	}
	if p.TimeSeconds == nil {
		p.TimeSeconds = map[string]int{}
	}
}

func openDB() (*sql.DB, error) {
	db, err := sql.Open("sqlite", filepath.Join(dataDir(), "docker-trainer.db"))
	if err != nil {
		return nil, err
	}
	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS progress (id INTEGER PRIMARY KEY CHECK (id = 1), data TEXT NOT NULL)`)
	return db, err
}

func openDBSafe() *sql.DB {
	db, err := openDB()
	if err != nil {
		return nil
	}
	return db
}

func loadProgress(db *sql.DB) *Progress {
	p := newProgress()
	if db == nil {
		return p
	}
	var data string
	if err := db.QueryRow(`SELECT data FROM progress WHERE id = 1`).Scan(&data); err != nil {
		return p
	}
	if err := json.Unmarshal([]byte(data), p); err == nil && p.Completed != nil {
		p.ensure()
		return p
	}
	var lg struct {
		XP        int             `json:"xp"`
		Completed map[string]bool `json:"completed"`
		Hints     map[string]int  `json:"hints_used"`
		Generated []Task          `json:"generated_tasks"`
	}
	if json.Unmarshal([]byte(data), &lg) == nil {
		p.XP = lg.XP
		if len(lg.Completed) > 0 {
			p.Completed["docker"] = lg.Completed
		}
		if len(lg.Hints) > 0 {
			p.Hints["docker"] = lg.Hints
		}
		for _, t := range lg.Generated {
			if t.Kind == "" {
				t.Kind = taskCmd
			}
			if t.Difficulty == 0 {
				t.Difficulty = 3
			}
			p.Generated["docker"] = append(p.Generated["docker"], t)
		}
	}
	p.ensure()
	return p
}

func todayStr() string { return time.Now().Format("2006-01-02") }

func prevDayStr(t string) string {
	d, err := time.Parse("2006-01-02", t)
	if err != nil {
		return ""
	}
	return d.AddDate(0, 0, -1).Format("2006-01-02")
}

func daysBetween(from, to string) int {
	f, err1 := time.Parse("2006-01-02", from)
	t, err2 := time.Parse("2006-01-02", to)
	if err1 != nil || err2 != nil {
		return 0
	}
	return int(t.Sub(f).Hours() / 24)
}

// ---------- экзамен ----------

const examKey = "__exam"

type ExamSession struct {
	Tasks   []Task
	Idx     int
	Results []bool
	Started time.Time
	Active  bool
}

// ---------- приложение ----------

type App struct {
	fyneApp fyne.App
	win     fyne.Window
	th      fyne.Theme
	db      *sql.DB
	cfg     *Config
	prog    *Progress
	ai      *AIClient

	courses   []Course
	courseIdx int
	frontier  int
	states    map[string]SandboxState
	history   map[string][]HistEntry
	stateTask map[string]string

	viewIdx        int
	tab            string
	mobile         bool
	mobileTabs     map[string]*widget.Button
	winMobileStack *fyne.Container
	busy           bool
	mentorBusy     bool
	chatLog        []string
	reviewKey      string

	cmdHist    []string
	cmdHistIdx int

	exam *ExamSession

	termText string
	chatText string

	// диктовка и хоткеи
	micBtn     *widget.Button
	recProc    *exec.Cmd
	recFile    string
	micBusy    bool
	capturing  string
	hotkeyBtns map[string]*widget.Button

	// таймер и автодополнение
	timerText *canvas.Text
	acBase    string
	acMatches []string
	acIdx     int

	// вложения в чат ментора
	attachBtn    *widget.Button
	attachLabel  *widget.Label
	attachRow    *fyne.Container
	attachClear  *widget.Button
	attachNames  []string
	attachTexts  []string
	attachImages []string

	list         *widget.List
	courseSel    *widget.Select
	taskTitle    *canvas.Text
	taskMeta     *canvas.Text
	theoryBox    *fyne.Container
	quizBox      *fyne.Container
	goalBox      *fyne.Container
	hintsBox     *fyne.Container
	goalCard     *fyne.Container
	theoryCard   *fyne.Container
	quizCard     *fyne.Container
	hintsCard    *fyne.Container
	tabTheoryBtn *widget.Button
	tabTermBtn   *widget.Button
	contentStack *fyne.Container
	termOut      *widget.Entry
	termGrid     *widget.TextGrid
	termScroll   *container.Scroll
	termIn       *termEntry
	termSpin     *widget.Activity
	chatOut      *widget.Entry
	chatScroll   *container.Scroll
	chatIn       *widget.Entry
	chatSendBtn  *widget.Button
	chatSpin     *widget.Activity
	genBtn       *widget.Button
	genSpin      *widget.Activity
	aiCourseBtn  *widget.Button
	rebuildBtn   *widget.Button
	examBtn      *widget.Button
	finishBtn    *widget.Button
	bookmarkBtn  *widget.Button
	xpText       *canvas.Text
}

func main() {
	fyneApp := app.NewWithID("com.vlad.termai")

	cfg := loadConfig()
	th := newClaudeTheme(cfg.FontPath)
	fyneApp.Settings().SetTheme(th)

	db := openDBSafe()

	a := &App{
		fyneApp: fyneApp, cfg: cfg, th: th, db: db,
		prog:      loadProgress(db),
		states:    map[string]SandboxState{},
		history:   map[string][]HistEntry{},
		stateTask: map[string]string{},
		tab:       "theory",
	}
	a.ai = NewAIClient(cfg)

	a.courses = builtinCourses()
	a.courses = append(a.courses, a.prog.Extra...)
	for i := range a.courses {
		cid := a.courses[i].ID
		a.courses[i].Tasks = append(a.courses[i].Tasks, a.prog.Generated[cid]...)
		for idx, t := range a.prog.Overrides[cid] {
			if idx >= 0 && idx < len(a.courses[i].Tasks) {
				a.courses[i].Tasks[idx] = t
			}
		}
	}
	if name := a.prog.LastCourse; name != "" {
		for i := range a.courses {
			if a.courses[i].ID == name {
				a.courseIdx = i
			}
		}
	}

	a.tasksOf(a.cur())
	a.buildUI()
	a.setupHotkeys()
	a.recomputeFrontier()
	a.resetCourseState()
	a.refreshHeader()
	a.refreshTimer()
	a.refreshCourseOptions()
	a.courseSel.SetSelected(a.cur().Title)
	a.mentorSay("mentor", "Привет! Я твой ИИ-наставник TERMAI. Формат задачи: теория с примерами → мини-тест → практика. Открывай любые задачи, создавай свои через «Задача от ИИ». docker ps / images / ls работают мгновенно и бесплатно. Сложное — в закладки ☆. Есть диктовка 🎙 (whisper.cpp), вложения в чат 📎 и горячие клавиши в настройках.")
	a.refreshList()
	a.selectTask(a.frontier, true)
	if a.mobile {
		a.switchTab("tasks")
	} else {
		a.switchTab("theory")
		a.win.Canvas().Focus(a.termIn)
	}

	a.startTimer()

	a.win.ShowAndRun()
}

// ---------- построение интерфейса ----------

func (a *App) buildUI() {
	a.mobile = fyne.CurrentDevice().IsMobile()
	a.mobileTabs = map[string]*widget.Button{}

	if a.mobile {
		a.win = a.fyneApp.NewWindow("TERMAI")
		a.win.Resize(fyne.NewSize(400, 760))
	} else {
		a.win = a.fyneApp.NewWindow("TERMAI — тренажёр с ИИ-наставником")
		a.win.Resize(fyne.NewSize(1240, 820))
	}

	a.xpText = canvas.NewText("", colMuted)
	a.xpText.TextSize = 12

	a.timerText = canvas.NewText("", colMuted)
	a.timerText.TextSize = 12

	a.courseSel = widget.NewSelect(nil, func(string) {})
	a.courseSel.PlaceHolder = "курс"
	a.courseSel.OnChanged = func(title string) {
		for i := range a.courses {
			if a.courses[i].Title == title && i != a.courseIdx {
				a.switchCourse(i)
			}
		}
	}

	a.genSpin = widget.NewActivity()
	a.genSpin.Hide()
	a.genBtn = widget.NewButtonWithIcon("Задача от ИИ", theme.ContentAddIcon(), a.openTaskDialog)
	a.aiCourseBtn = widget.NewButtonWithIcon("Курс от ИИ", theme.FolderOpenIcon(), a.openNewCourseDialog)
	a.rebuildBtn = widget.NewButtonWithIcon("Пересобрать", theme.ViewRefreshIcon(), a.openRebuildDialog)
	a.examBtn = widget.NewButton("Экзамен", a.startExam)
	reviewBtn := widget.NewButton("Повторение", a.showReview)
	statBtn := widget.NewButtonWithIcon("", theme.InfoIcon(), a.showStats)
	settingsBtn := widget.NewButtonWithIcon("", theme.SettingsIcon(), a.openSettings)

	var header fyne.CanvasObject
	if a.mobile {
		moreBtn := widget.NewButtonWithIcon("", theme.MoreHorizontalIcon(), a.showMoreMenu)
		top := container.NewBorder(nil, nil, a.xpText,
			container.NewHBox(moreBtn, settingsBtn), a.courseSel)
		header = container.NewVBox(container.NewPadded(top), widget.NewSeparator())
	} else {
		headerRow := container.NewBorder(nil, nil, container.NewHBox(a.xpText, a.timerText), container.NewHBox(
			container.NewGridWrap(fyne.NewSize(180, 37), a.courseSel),
			a.examBtn, reviewBtn, a.genSpin, a.genBtn, a.aiCourseBtn, a.rebuildBtn, statBtn, settingsBtn,
		))
		header = container.NewVBox(container.NewPadded(headerRow), widget.NewSeparator())
	}

	a.list = widget.NewList(
		func() int { return len(a.cur().Tasks) },
		func() fyne.CanvasObject {
			return widget.NewRichText(&widget.TextSegment{
				Text:  "● Название задачи — пример строки",
				Style: widget.RichTextStyle{Inline: true},
			})
		},
		func(i widget.ListItemID, o fyne.CanvasObject) {
			rt := o.(*widget.RichText)
			rt.Segments = a.taskRowSegments(int(i))
			rt.Refresh()
		},
	)
	a.list.OnSelected = func(i widget.ListItemID) { a.onTaskClicked(int(i)) }
	listPane := container.NewPadded(a.list)

	a.taskTitle = canvas.NewText("", colFg)
	a.taskTitle.TextSize = 18
	a.taskTitle.TextStyle = fyne.TextStyle{Bold: true}

	a.taskMeta = canvas.NewText("", colMuted)
	a.taskMeta.TextSize = 12

	a.theoryBox = container.NewVBox()
	a.quizBox = container.NewVBox()
	a.goalBox = container.NewVBox()
	a.hintsBox = container.NewVBox()

	a.finishBtn = widget.NewButton("Завершить задачу", a.onFinishTask)
	a.finishBtn.Importance = widget.HighImportance
	a.bookmarkBtn = widget.NewButton("☆ В закладки", a.toggleBookmark)
	actions := container.NewHBox(a.finishBtn, a.bookmarkBtn)

	goalCaption := caption("ЗАДАЧА", colAccent)
	_ = goalCaption
	_ = caption

	a.goalCard = sectionCard("ЗАДАЧА", colAccent, a.goalBox)
	a.theoryCard = sectionCard("ТЕОРИЯ", colMuted, a.theoryBox)
	a.quizCard = sectionCard("ТЕСТ ПО ТЕОРИИ", colAccent, a.quizBox)
	a.hintsCard = sectionCard("ПОДСКАЗКИ", colMuted, a.hintsBox)

	taskContent := container.NewVBox(
		a.taskTitle, a.taskMeta,
		spacerV(12),
		a.goalCard,
		spacerV(10),
		a.theoryCard,
		spacerV(10),
		a.quizCard,
		spacerV(14), actions,
		spacerV(10),
		a.hintsCard,
	)
	theoryPane := panel(container.NewScroll(taskContent), colPanel)

	termBg := canvas.NewRectangle(colTerm)
	var termInner *fyne.Container
	if a.mobile {
		a.termGrid = widget.NewTextGrid()
		a.termGrid.SetText(a.termText)
		a.termScroll = container.NewScroll(a.termGrid)
		termInner = container.NewStack(termBg, a.termScroll)
	} else {
		a.termOut = widget.NewMultiLineEntry()
		a.termOut.TextStyle = fyne.TextStyle{Monospace: true}
		a.termOut.Wrapping = fyne.TextWrapWord
		a.termOut.OnChanged = func(s string) {
			if s != a.termText {
				a.termOut.SetText(a.termText)
			}
		}
		a.termScroll = container.NewScroll(a.termOut)
		termInner = container.NewStack(termBg, a.termScroll)
	}

	termCaption := canvas.NewText("терминал", colMuted)
	termCaption.TextSize = 12
	resetTermBtn := widget.NewButton("Очистить", func() {
		a.termText = ""
		a.termLine("  (вывод терминала очищен)")
		a.refreshTerminal()
	})
	resetSandboxBtn := widget.NewButton("Сброс песочницы", a.confirmResetSandbox)
	termTop := container.NewBorder(nil, nil, termCaption, container.NewHBox(resetSandboxBtn, resetTermBtn))

	a.termSpin = widget.NewActivity()
	a.termSpin.Hide()
	prompt := canvas.NewText("$ ", colAccent)
	prompt.TextSize = 14
	prompt.TextStyle = fyne.TextStyle{Monospace: true}

	a.termIn = &termEntry{Entry: widget.NewEntry(), app: a}
	a.termIn.PlaceHolder = "команда или ответ… (Tab — автодополнение, ↑/↓ — история)"
	a.termIn.TextStyle = fyne.TextStyle{Monospace: true}
	a.termIn.OnSubmitted = a.runCommand

	var termField fyne.CanvasObject = a.termIn
	if a.mobile {
		termField = fixedHeight(52, a.termIn)
	}
	termInput := container.NewBorder(nil, nil, container.NewHBox(a.termSpin, prompt), nil, termField)
	termPane := container.NewStack(termBg,
		container.NewPadded(container.NewBorder(
			container.NewVBox(termTop, spacerV(6)), container.NewPadded(termInput), nil, nil, termInner),
		))

	a.tabTheoryBtn = widget.NewButton("Теория", nil)
	a.tabTermBtn = widget.NewButton("Терминал", nil)
	filesBtn := widget.NewButtonWithIcon("Файлы", theme.FolderIcon(), a.showFiles)
	tabs := container.NewBorder(nil, nil,
		container.NewHBox(a.tabTheoryBtn, a.tabTermBtn), filesBtn)

	a.chatOut = widget.NewMultiLineEntry()
	a.chatOut.Wrapping = fyne.TextWrapWord
	a.chatOut.OnChanged = func(s string) {
		if s != a.chatText {
			a.chatOut.SetText(a.chatText)
		}
	}
	a.chatScroll = container.NewScroll(a.chatOut)

	chatCaption := canvas.NewText("ментор", colMuted)
	chatCaption.TextSize = 12

	a.chatSpin = widget.NewActivity()
	a.chatSpin.Hide()
	a.chatIn = widget.NewEntry()
	a.chatIn.PlaceHolder = "Спроси ментора о задаче, синтаксисе, ошибке…"
	a.chatIn.OnSubmitted = func(string) { a.sendChat() }
	a.chatSendBtn = widget.NewButton("Отправить", a.sendChat)
	a.chatSendBtn.Importance = widget.HighImportance

	a.attachBtn = widget.NewButtonWithIcon("", theme.FileIcon(), a.attachFile)
	var chatInput fyne.CanvasObject
	if !a.mobile {
		a.micBtn = widget.NewButtonWithIcon("Диктовать", theme.FileAudioIcon(), a.onMicTap)
		chatInput = container.NewBorder(nil, nil, container.NewHBox(a.attachBtn, a.micBtn), a.chatSendBtn, a.chatIn)
	} else {
		chatInput = container.NewBorder(nil, nil, a.attachBtn, a.chatSendBtn, fixedHeight(52, a.chatIn))
	}

	a.attachLabel = widget.NewLabel("")
	a.attachLabel.Wrapping = fyne.TextWrapWord
	a.attachClear = widget.NewButton("✕", a.clearAttachments)
	a.attachRow = container.NewBorder(nil, nil, nil, a.attachClear, a.attachLabel)
	a.attachRow.Hide()

	chatCol := container.NewVBox(
		container.NewPadded(chatCaption),
		fixedHeight(150, a.chatScroll),
		container.NewPadded(a.attachRow),
		container.NewPadded(chatInput),
	)
	chatPane := panel(chatCol, colPanel)

	var root fyne.CanvasObject
	if a.mobile {
		// ментор — полноэкранный таб
		chatFull := container.NewBorder(
			container.NewPadded(chatCaption),
			container.NewPadded(chatInput),
			nil, nil, a.chatScroll,
		)
		stack := container.NewStack(listPane, theoryPane, termPane, chatFull)
		a.winMobileStack = stack
		navDefs := []struct{ key, title string }{
			{"tasks", "Задачи"}, {"theory", "Теория"}, {"term", "Терминал"}, {"chat", "Ментор"},
		}
		for _, nd := range navDefs {
			nd := nd
			b := widget.NewButton(nd.title, nil)
			a.mobileTabs[nd.key] = b
			b.OnTapped = func() { a.switchTab(mobileTabName(nd.key)) }
		}
		nav := container.NewGridWithColumns(4,
			a.mobileTabs["tasks"], a.mobileTabs["theory"], a.mobileTabs["term"], a.mobileTabs["chat"])
		a.showMobileTab("tasks")
		root = container.NewBorder(header, container.NewPadded(fixedHeight(58, nav)), nil, nil, stack)
	} else {
		a.contentStack = container.NewStack(theoryPane, termPane)
		right := container.NewBorder(container.NewPadded(tabs), nil, nil, nil, a.contentStack)
		split := container.NewHSplit(listPane, right)
		split.Offset = 0.24
		root = container.NewBorder(header, container.NewPadded(chatPane), nil, nil, split)
	}
	a.win.SetContent(root)

	a.tabTheoryBtn.OnTapped = func() { a.switchTab("theory") }
	a.tabTermBtn.OnTapped = func() { a.switchTab("terminal") }

	a.win.SetOnClosed(func() { a.saveProgress() })
}

// termEntry — терминальный ввод с перехватом Tab (автодополнение) и ↑/↓ (история)
// до обработки стандартной логикой Entry.
type termEntry struct {
	*widget.Entry
	app *App
}

func (t *termEntry) AcceptsTab() bool { return true }

func (t *termEntry) TypedKey(e *fyne.KeyEvent) {
	switch e.Name {
	case fyne.KeyTab:
		t.app.autocomplete()
		return
	case fyne.KeyUp, fyne.KeyDown:
		t.app.termKeyDown(e)
		return
	}
	t.Entry.TypedKey(e)
}

func caption(text string, c color.Color) *canvas.Text {
	t := canvas.NewText(text, c)
	t.TextSize = 12
	t.TextStyle = fyne.TextStyle{Bold: true}
	return t
}

// sectionCard — карточка-секция панели задачи: заголовок с левой акцентной полосой,
// скруглённый фон с рамкой и внутренним отступом. content — это контейнер, чьи
// .Objects перезаписываются в renderTaskPanel.
func sectionCard(title string, accent color.Color, content *fyne.Container) *fyne.Container {
	head := caption(title, accent)
	body := container.NewVBox(head, spacerV(6), content)

	bg := canvas.NewRectangle(nrgba(0x252423))
	bg.CornerRadius = 6
	border := canvas.NewRectangle(color.NRGBA{A: 0})
	border.StrokeColor = nrgba(0x2c2b29)
	border.StrokeWidth = 1
	border.CornerRadius = 6

	bar := container.NewGridWrap(fyne.NewSize(3, 1), canvas.NewRectangle(accent))
	inner := container.NewBorder(nil, nil, bar, nil, container.NewPadded(body))
	return container.NewStack(bg, border, inner)
}

func (a *App) termKeyDown(e *fyne.KeyEvent) {
	switch e.Name {
	case fyne.KeyUp:
		if len(a.cmdHist) == 0 {
			return
		}
		if a.cmdHistIdx > 0 {
			a.cmdHistIdx--
		}
		a.termIn.SetText(a.cmdHist[a.cmdHistIdx])
	case fyne.KeyDown:
		if a.cmdHistIdx < len(a.cmdHist)-1 {
			a.cmdHistIdx++
			a.termIn.SetText(a.cmdHist[a.cmdHistIdx])
		} else {
			a.cmdHistIdx = len(a.cmdHist)
			a.termIn.SetText("")
		}
	}
}

// ---------- Tab-автодополнение ----------

var dockerSubcommands = []string{
	"ps", "images", "run", "rm", "rmi", "stop", "start", "restart", "exec", "logs",
	"pull", "build", "create", "attach", "commit", "cp", "inspect", "volume", "network",
	"compose", "system", "save", "load", "tag", "push",
}

func (a *App) autocomplete() {
	text := a.termIn.Text
	idx := strings.LastIndexAny(text, " \t")
	base := ""
	token := text
	if idx >= 0 {
		base = text[:idx+1]
		token = text[idx+1:]
	}

	// продолжаем циклический перебор уже найденных вариантов
	if len(a.acMatches) > 0 && a.acIdx < len(a.acMatches) &&
		a.acBase == base && text == base+a.acMatches[a.acIdx] {
		a.acIdx = (a.acIdx + 1) % len(a.acMatches)
		a.termIn.SetText(base + a.acMatches[a.acIdx])
		a.termIn.Refresh()
		return
	}

	cands := a.autocompleteCandidates(base, token)
	if len(cands) == 0 {
		a.acMatches = nil
		return
	}
	a.acBase = base
	a.acMatches = cands
	a.acIdx = 0
	a.termIn.SetText(base + cands[0])
	a.termIn.Refresh()
}

func (a *App) autocompleteCandidates(base, token string) []string {
	fields := strings.Fields(base)
	var pool []string
	switch {
	case len(fields) == 0:
		pool = []string{"docker", "ls", "cat", "pwd", "echo", "cd", "help", "state", "clear"}
	case fields[0] == "docker":
		pool = a.dockerCandidates(fields)
	case fields[0] == "cat" || fields[0] == "ls" || fields[0] == "cd":
		pool = fileNames(a.state())
	default:
		pool = []string{"docker", "ls", "cat", "pwd", "echo", "cd", "help", "state", "clear"}
	}
	return prefixMatch(pool, token)
}

func (a *App) dockerCandidates(fields []string) []string {
	if len(fields) == 1 {
		return dockerSubcommands
	}
	sub := fields[1]
	st := a.state()
	switch sub {
	case "rm", "stop", "start", "restart", "exec", "logs", "inspect", "attach", "commit", "cp":
		return containerNames(st)
	case "rmi", "run":
		return imageNames(st)
	case "pull":
		return append(imageNames(st), "nginx:alpine", "redis:alpine", "alpine:latest", "hello-world:latest", "python:3.12-slim", "ubuntu:22.04")
	case "volume":
		if len(fields) == 2 {
			return []string{"ls", "create", "rm", "inspect"}
		}
		return volumeNames(st)
	case "network":
		if len(fields) == 2 {
			return []string{"ls", "create", "rm", "inspect"}
		}
		return networkNames(st)
	}
	return nil
}

func prefixMatch(pool []string, token string) []string {
	var out []string
	seen := map[string]bool{}
	for _, c := range pool {
		if c == "" || seen[c] {
			continue
		}
		if token == "" || strings.HasPrefix(c, token) {
			seen[c] = true
			out = append(out, c)
		}
	}
	sort.Strings(out)
	return out
}

func containerNames(st SandboxState) []string {
	out := make([]string, 0, len(st.Containers))
	for n := range st.Containers {
		out = append(out, n)
	}
	return out
}

func imageNames(st SandboxState) []string {
	out := make([]string, 0, len(st.Images))
	for k := range st.Images {
		out = append(out, k)
	}
	return out
}

func fileNames(st SandboxState) []string {
	out := make([]string, 0, len(st.Files))
	for n := range st.Files {
		out = append(out, n)
	}
	return out
}

func volumeNames(st SandboxState) []string {
	out := make([]string, 0, len(st.Volumes))
	for v := range st.Volumes {
		out = append(out, v)
	}
	return out
}

func networkNames(st SandboxState) []string {
	return append([]string(nil), st.Networks...)
}

func mobileTabName(key string) string {
	if key == "term" {
		return "terminal"
	}
	return key
}

func (a *App) showMobileTab(key string) {
	if a.winMobileStack == nil {
		return
	}
	idx := map[string]int{"tasks": 0, "theory": 1, "term": 2, "chat": 3}[key]
	for i, o := range a.winMobileStack.Objects {
		if i == idx {
			o.Show()
		} else {
			o.Hide()
		}
	}
	for n, b := range a.mobileTabs {
		if n == key {
			b.Importance = widget.HighImportance
		} else {
			b.Importance = widget.MediumImportance
		}
		b.Refresh()
	}
}

func (a *App) switchTab(tab string) {
	a.tab = tab
	if a.mobile {
		key := tab
		if key == "terminal" {
			key = "term"
		}
		switch key {
		case "tasks", "theory", "term", "chat":
			a.showMobileTab(key)
		}
		return
	}
	if tab == "theory" {
		a.tabTheoryBtn.Importance = widget.HighImportance
		a.tabTermBtn.Importance = widget.MediumImportance
		a.contentStack.Objects[0].Show()
		a.contentStack.Objects[1].Hide()
	} else {
		a.tabTheoryBtn.Importance = widget.MediumImportance
		a.tabTermBtn.Importance = widget.HighImportance
		a.contentStack.Objects[0].Hide()
		a.contentStack.Objects[1].Show()
		a.win.Canvas().Focus(a.termIn)
	}
	a.tabTheoryBtn.Refresh()
	a.tabTermBtn.Refresh()
}

func (a *App) showMoreMenu() {
	content := container.NewVBox(
		widget.NewButton("Экзамен", a.startExam),
		widget.NewButton("Повторение", a.showReview),
		widget.NewButton("Задача от ИИ", a.openTaskDialog),
		widget.NewButton("Курс от ИИ", a.openNewCourseDialog),
		widget.NewButton("Пересобрать курс", a.openRebuildDialog),
		widget.NewButton("Файлы песочницы", a.showFiles),
		widget.NewButton("Статистика и достижения", a.showStats),
	)
	d := dialog.NewCustom("Ещё", "Закрыть", content, a.win)
	d.Resize(fyne.NewSize(360, 460))
	d.Show()
}

// ---------- доступ к текущему курсу ----------

func (a *App) cur() *Course { return &a.courses[a.courseIdx] }

func (a *App) stateKey() string {
	if a.exam != nil && a.exam.Active {
		return examKey
	}
	return a.cur().ID
}

func (a *App) tasksOf(c *Course) []Task {
	for i := range c.Tasks {
		if c.Tasks[i].Kind == "" {
			c.Tasks[i].Kind = taskCmd
		}
		if c.Tasks[i].Difficulty == 0 {
			c.Tasks[i].Difficulty = 2
		}
	}
	return c.Tasks
}

func (a *App) completed() map[string]bool {
	cid := a.cur().ID
	if a.prog.Completed[cid] == nil {
		a.prog.Completed[cid] = map[string]bool{}
	}
	return a.prog.Completed[cid]
}

func (a *App) hintsUsed() map[string]int {
	cid := a.cur().ID
	if a.prog.Hints[cid] == nil {
		a.prog.Hints[cid] = map[string]int{}
	}
	return a.prog.Hints[cid]
}

func (a *App) quizDone(taskID string) bool {
	m := a.prog.QuizDone[a.cur().ID]
	return m != nil && m[taskID]
}

func (a *App) setQuizDone(taskID string) {
	cid := a.cur().ID
	if a.prog.QuizDone[cid] == nil {
		a.prog.QuizDone[cid] = map[string]bool{}
	}
	a.prog.QuizDone[cid][taskID] = true
}

func (a *App) recomputeFrontier() {
	tasks := a.cur().Tasks
	done := a.completed()
	a.frontier = len(tasks)
	for i := range tasks {
		if !done[tasks[i].ID] {
			a.frontier = i
			break
		}
	}
}

func (a *App) resetCourseState() {
	cid := a.cur().ID
	if _, ok := a.states[cid]; !ok {
		if a.frontier < len(a.cur().Tasks) {
			a.states[cid] = cloneState(a.cur().Tasks[a.frontier].Start)
			a.stateTask[cid] = a.cur().Tasks[a.frontier].ID
		} else {
			a.states[cid] = baseState()
		}
	}
	if _, ok := a.history[cid]; !ok {
		a.history[cid] = nil
	}
}

func (a *App) ensureStateForTask(t *Task) {
	if t == nil || (a.exam != nil && a.exam.Active) {
		return
	}
	cid := a.cur().ID
	if a.stateTask[cid] == t.ID {
		return
	}
	a.states[cid] = cloneState(t.Start)
	a.history[cid] = nil
	a.stateTask[cid] = t.ID
}

// confirmResetSandbox — сброс состояния песочницы текущей задачи к началу.
func (a *App) confirmResetSandbox() {
	if a.exam != nil && a.exam.Active {
		dialog.ShowInformation("Сброс песочницы", "Во время экзамена сброс недоступен.", a.win)
		return
	}
	t := a.currentTask()
	if t == nil {
		dialog.ShowInformation("Сброс песочницы", "Активной задачи нет — сбрасывать нечего.", a.win)
		return
	}
	dialog.NewConfirm("Сброс песочницы",
		"Вернуть терминал и состояние песочницы к началу задачи «"+t.Title+"»?\nИстория команд будет очищена (прогресс и тесты не пострадают).",
		func(ok bool) {
			if ok {
				a.resetSandbox(t)
			}
		}, a.win).Show()
}

func (a *App) resetSandbox(t *Task) {
	cid := a.cur().ID
	a.states[cid] = cloneState(t.Start)
	a.history[cid] = nil
	a.stateTask[cid] = t.ID
	a.termLine("")
	a.termLine("── песочница сброшена к началу задачи: " + t.Title + " ──")
	a.refreshTerminal()
}

func (a *App) switchCourse(i int) {
	if a.exam != nil && a.exam.Active {
		a.mentorSay("system", "Сначала заверши экзамен.")
		a.courseSel.SetSelected(a.cur().Title)
		return
	}
	a.courseIdx = i
	a.reviewKey = ""
	a.prog.LastCourse = a.cur().ID
	a.saveProgress()
	a.tasksOf(a.cur())
	a.recomputeFrontier()
	a.resetCourseState()
	a.viewIdx = 0
	a.refreshCourseOptions()
	a.courseSel.SetSelected(a.cur().Title)
	a.refreshList()
	a.refreshHeader()
	a.termLine("")
	a.termLine("── Курс: " + a.cur().Title + " ──")
	if len(a.cur().Tasks) == 0 {
		a.termLine("  …ИИ пишет первую задачу курса")
		a.refreshTerminal()
		a.genNextTask(true)
	} else {
		a.refreshTerminal()
		a.selectTask(a.frontier, true)
	}
	a.switchTab("theory")
}

func (a *App) refreshCourseOptions() {
	titles := make([]string, len(a.courses))
	for i := range a.courses {
		titles[i] = a.courses[i].Title
	}
	a.courseSel.Options = titles
	a.courseSel.Refresh()
}

func (a *App) refreshList() { a.list.Refresh() }

// ---------- панель задачи ----------

func (a *App) taskRowSegments(i int) []widget.RichTextSegment {
	tasks := a.cur().Tasks
	t := &tasks[i]
	var col fyne.ThemeColorName
	var glyph string
	switch {
	case a.completed()[t.ID]:
		glyph, col = "✓  ", theme.ColorNameSuccess
	case i == a.frontier:
		glyph, col = "●  ", theme.ColorNamePrimary
	default:
		glyph, col = "○  ", colNameMuted
	}
	if t.Kind == taskQuiz {
		glyph += "? "
	}
	st := widget.RichTextStyle{Inline: true, ColorName: col}
	return []widget.RichTextSegment{
		&widget.TextSegment{Text: glyph, Style: st},
		&widget.TextSegment{Text: t.Title, Style: st},
	}
}

func (a *App) renderTaskPanel() {
	if a.exam != nil && a.exam.Active && a.exam.Idx < len(a.exam.Tasks) {
		ex := a.exam
		t := &ex.Tasks[ex.Idx]
		a.taskTitle.Text = fmt.Sprintf("Экзамен · задача %d/5 — %s", ex.Idx+1, t.Title)
		a.taskMeta.Text = "время: " + time.Since(ex.Started).Round(time.Second).String() +
			" · верных: " + fmt.Sprint(len(ex.Results)) + "/5"
		a.goalBox.Objects = []fyne.CanvasObject{accentGoal(t.Goal)}
		a.theoryBox.Objects = paraList(t.Theory)
		a.quizBox.Objects = nil
		a.hintsBox.Objects = nil
		a.finishBtn.SetText("Сдать задачу")
		a.finishBtn.Show()
		a.bookmarkBtn.Hide()
		a.refreshTaskWidgets()
		return
	}

	tasks := a.cur().Tasks
	if a.viewIdx < 0 || a.viewIdx >= len(tasks) {
		a.taskTitle.Text = "Задачи курса закончились"
		a.taskMeta.Text = "ИИ напишет следующую автоматически — или жми «Задача от ИИ» и опиши свою"
		a.goalBox.Objects = []fyne.CanvasObject{mdTheory(
			"Своя задача — в любой момент: кнопка **«Задача от ИИ»** в шапке. Не нравится подача курса — **«Пересобрать»**.")}
		a.theoryBox.Objects = nil
		a.quizBox.Objects = nil
		a.hintsBox.Objects = nil
		a.finishBtn.Hide()
		a.bookmarkBtn.Hide()
		a.refreshTaskWidgets()
		return
	}
	t := &tasks[a.viewIdx]

	a.taskTitle.Text = t.Title
	kindWord := "практика"
	if t.Kind == taskQuiz {
		kindWord = "тест"
	}
	d := clamp(t.Difficulty, 1, 5)
	dots := strings.Repeat("●", d) + strings.Repeat("○", 5-d)
	meta := fmt.Sprintf("%s · сложность %s · +%d XP · id: %s", kindWord, dots, 15*d+15, t.ID)
	if a.completed()[t.ID] {
		meta += " · решена"
	}
	if a.reviewKey != "" {
		meta += " · РЕЖИМ ПОВТОРЕНИЯ"
	}
	a.taskMeta.Text = meta

	a.goalBox.Objects = []fyne.CanvasObject{accentGoal(t.Goal)}
	a.theoryBox.Objects = paraList(t.Theory)

	needQuiz := len(t.Quiz) > 0 && !a.quizDone(t.ID) && !a.completed()[t.ID]
	if needQuiz {
		a.quizBox.Objects = a.buildQuiz(t)
		a.finishBtn.Hide()
		a.hintsBox.Objects = nil
		a.bookmarkBtn.Show()
		a.bookmarkBtn.SetText(bookmarkText(a, t.ID))
	} else {
		a.quizBox.Objects = nil
		if a.reviewKey != "" || !a.completed()[t.ID] {
			a.finishBtn.SetText("Завершить задачу")
			a.finishBtn.Show()
		} else {
			a.finishBtn.Hide()
		}
		a.renderHints()
		a.bookmarkBtn.SetText(bookmarkText(a, t.ID))
		a.bookmarkBtn.Show()
	}
	if a.reviewKey != "" {
		a.bookmarkBtn.Hide()
	}

	a.refreshTaskWidgets()
}

func bookmarkText(a *App, taskID string) string {
	key := a.cur().ID + "|" + taskID
	if _, ok := a.prog.Bookmarks[key]; ok {
		return "★ В закладках"
	}
	return "☆ В закладки"
}

func (a *App) refreshTaskWidgets() {
	a.taskTitle.Refresh()
	a.taskMeta.Refresh()
	a.theoryBox.Refresh()
	a.quizBox.Refresh()
	a.goalBox.Refresh()
	a.hintsBox.Refresh()
	a.finishBtn.Refresh()
	a.bookmarkBtn.Refresh()
	a.refreshCards()
}

// refreshCards — показываем только те карточки, в которых есть содержимое,
// чтобы пустые секции (тест/подсказки) не оставляли «висячие» заголовки.
func (a *App) refreshCards() {
	setCardVisible(a.goalCard, len(a.goalBox.Objects) > 0)
	setCardVisible(a.theoryCard, len(a.theoryBox.Objects) > 0)
	setCardVisible(a.quizCard, len(a.quizBox.Objects) > 0)
	setCardVisible(a.hintsCard, len(a.hintsBox.Objects) > 0)
}

func setCardVisible(c *fyne.Container, v bool) {
	if c == nil {
		return
	}
	if v {
		c.Show()
	} else {
		c.Hide()
	}
}

func (a *App) buildQuiz(t *Task) []fyne.CanvasObject {
	type snap struct {
		opts    []string
		correct int
	}
	snaps := make([]snap, len(t.Quiz))
	radios := make([]*widget.RadioGroup, len(t.Quiz))

	cid := a.cur().ID
	if a.prog.QuizTries[cid] == nil {
		a.prog.QuizTries[cid] = map[string]int{}
	}

	var objs []fyne.CanvasObject
	for i, q := range t.Quiz {
		snaps[i] = snap{opts: append([]string(nil), q.Options...), correct: q.Correct}
		ql := widget.NewLabel(fmt.Sprintf("%d. %s", i+1, q.Question))
		ql.Wrapping = fyne.TextWrapWord
		r := widget.NewRadioGroup(q.Options, func(string) {})
		radios[i] = r
		objs = append(objs, ql, r, spacerV(6))
	}

	total := len(snaps)
	check := widget.NewButton("Проверить тест", func() {
		right := 0
		for i := range radios {
			sel := radios[i].Selected
			if sel == "" {
				a.resultDialog("Тест", "Сначала ответь на все вопросы.", false)
				return
			}
			if sel == snaps[i].opts[snaps[i].correct] {
				right++
			}
		}
		a.prog.QuizTries[cid][t.ID]++
		if right == total {
			if a.prog.QuizTries[cid][t.ID] == 1 {
				a.grant("quiz-perfect")
			}
			a.setQuizDone(t.ID)
			a.saveProgress()
			a.termLine("  ✓ тест пройден: " + t.Title + " — практика открыта")
			a.refreshTerminal()
			a.renderTaskPanel()
		} else {
			a.saveProgress()
			a.resultDialog("Есть ошибки",
				fmt.Sprintf("Верных ответов: %d из %d.\nПеречитай теорию (обрати внимание на примеры команд) и попробуй снова.", right, total), false)
		}
	})
	check.Importance = widget.HighImportance
	return append(objs, check)
}

func paraList(items []string) []fyne.CanvasObject {
	objs := make([]fyne.CanvasObject, 0, len(items))
	for _, s := range items {
		objs = append(objs, mdTheory(s))
	}
	return objs
}

func accentGoal(goal string) fyne.CanvasObject {
	l := widget.NewLabel(goal)
	l.Wrapping = fyne.TextWrapWord
	bar := container.NewGridWrap(fyne.NewSize(3, 1), canvas.NewRectangle(colAccent))
	return container.NewBorder(nil, nil, bar, nil, container.NewPadded(l))
}

func hintLabel(text string) fyne.CanvasObject {
	rt := widget.NewRichText(&widget.TextSegment{
		Text:  text,
		Style: widget.RichTextStyle{ColorName: colNameMuted},
	})
	rt.Wrapping = fyne.TextWrapWord
	return rt
}

func (a *App) renderHints() {
	a.hintsBox.Objects = nil
	defer a.hintsBox.Refresh()
	tasks := a.cur().Tasks
	if a.viewIdx < 0 || a.viewIdx >= len(tasks) {
		return
	}
	t := &tasks[a.viewIdx]
	used := a.hintsUsed()[t.ID]
	for i := 0; i < len(t.Hints) && i < 2; i++ {
		if i < used {
			a.hintsBox.Objects = append(a.hintsBox.Objects, hintLabel(t.Hints[i]))
		} else {
			idx, task := i, t
			a.hintsBox.Objects = append(a.hintsBox.Objects,
				widget.NewButton(fmt.Sprintf("Подсказка %d", i+1), func() {
					a.hintsUsed()[task.ID] = idx + 1
					a.saveProgress()
					a.renderHints()
				}))
		}
	}
}

// ---------- markdown → RichText (теория) ----------

func mdTheory(md string) fyne.CanvasObject {
	rt := widget.NewRichText(mdToSegments(md)...)
	rt.Wrapping = fyne.TextWrapWord
	return rt
}

func inlineSegments(s string, base widget.RichTextStyle) []widget.RichTextSegment {
	var out []widget.RichTextSegment
	emit := func(t string, st widget.RichTextStyle) {
		if t == "" {
			return
		}
		st.Inline = true
		out = append(out, &widget.TextSegment{Text: t, Style: st})
	}
	var plain strings.Builder
	flush := func() { emit(plain.String(), base); plain.Reset() }
	i := 0
	for i < len(s) {
		switch {
		case strings.HasPrefix(s[i:], "**"):
			j := strings.Index(s[i+2:], "**")
			if j >= 0 {
				flush()
				st := base
				st.TextStyle.Bold = true
				emit(s[i+2:i+2+j], st)
				i += j + 4
				continue
			}
			plain.WriteString("**")
			i += 2
		case s[i] == '`':
			j := strings.Index(s[i+1:], "`")
			if j >= 0 {
				flush()
				emit(s[i+1:i+1+j], widget.RichTextStyle{
					ColorName: colNameMuted,
					TextStyle: fyne.TextStyle{Monospace: true},
				})
				i += j + 2
				continue
			}
			plain.WriteByte('`')
			i++
		case s[i] == '*':
			j := strings.Index(s[i+1:], "*")
			if j > 0 {
				flush()
				st := base
				st.TextStyle.Italic = true
				emit(s[i+1:i+1+j], st)
				i += j + 2
				continue
			}
			plain.WriteByte('*')
			i++
		default:
			plain.WriteByte(s[i])
			i++
		}
	}
	flush()
	return out
}

func mdToSegments(md string) []widget.RichTextSegment {
	var segs []widget.RichTextSegment
	lines := strings.Split(strings.ReplaceAll(md, "\r\n", "\n"), "\n")
	inCode := false
	var code []string
	flushCode := func() {
		if len(code) == 0 {
			return
		}
		segs = append(segs, &widget.TextSegment{
			Text: strings.Join(code, "\n"),
			Style: widget.RichTextStyle{
				ColorName: colNameMuted,
				TextStyle: fyne.TextStyle{Monospace: true},
			},
		})
		code = nil
	}
	for _, ln := range lines {
		tr := strings.TrimSpace(ln)
		if strings.HasPrefix(tr, "```") {
			if inCode {
				flushCode()
			}
			inCode = !inCode
			continue
		}
		if inCode {
			code = append(code, ln)
			continue
		}
		switch {
		case tr == "":
			segs = append(segs, &widget.ParagraphSegment{})
		case strings.HasPrefix(tr, "#"):
			t := strings.TrimLeft(tr, "# ")
			segs = append(segs, &widget.TextSegment{
				Text:  t,
				Style: widget.RichTextStyle{TextStyle: fyne.TextStyle{Bold: true}},
			})
			segs = append(segs, &widget.ParagraphSegment{})
		case strings.HasPrefix(tr, "- "), strings.HasPrefix(tr, "* "):
			segs = append(segs, inlineSegments("•  "+tr[2:], widget.RichTextStyle{})...)
			segs = append(segs, &widget.ParagraphSegment{})
		default:
			segs = append(segs, inlineSegments(tr, widget.RichTextStyle{})...)
			segs = append(segs, &widget.ParagraphSegment{})
		}
	}
	if inCode {
		flushCode()
	}
	return segs
}

// ---------- терминал ----------

func (a *App) termLine(text string) {
	a.termText += text + "\n"
}

func (a *App) refreshTerminal() {
	if a.mobile && a.termGrid != nil {
		a.termGrid.SetText(a.termText)
	} else if a.termOut != nil {
		a.termOut.SetText(a.termText)
	}
	a.termScroll.ScrollToBottom()
}

func (a *App) state() SandboxState { return a.states[a.stateKey()] }

func (a *App) statePtr() *SandboxState {
	s := a.states[a.stateKey()]
	return &s
}

func (a *App) runCommand(cmd string) {
	cmd = strings.TrimSpace(cmd)
	if cmd == "" {
		return
	}
	a.termIn.SetText("")
	a.termLine("$ " + cmd)

	if len(a.cmdHist) == 0 || a.cmdHist[len(a.cmdHist)-1] != cmd {
		a.cmdHist = append(a.cmdHist, cmd)
	}
	a.cmdHistIdx = len(a.cmdHist)

	switch strings.ToLower(cmd) {
	case "clear":
		a.termText = ""
		a.refreshTerminal()
		return
	case "help":
		a.termLine("  Локальные (мгновенно, без ИИ): docker ps/ps -a/images/volume ls/network ls/rm/rmi/stop/start/restart, ls, cat, pwd, echo, cd, state, clear, help.")
		a.termLine("  Всё остальное исполняет ИИ-симулятор. Тесты quiz: пиши ответ текстом. Tab — автодополнение, ↑/↓ — история.")
		a.refreshTerminal()
		return
	case "state":
		if data, err := json.MarshalIndent(a.state(), "  ", "  "); err == nil {
			a.termLine(string(data))
		}
		a.refreshTerminal()
		return
	}
	a.refreshTerminal()

	if a.busy {
		a.termLine("  …предыдущая команда ещё выполняется")
		a.refreshTerminal()
		return
	}

	// локальный fast-path: мгновенно и бесплатно, без ИИ
	if handled, out := a.tryLocalCommand(cmd); handled {
		if strings.TrimSpace(out) != "" {
			a.termLine(out)
		}
		key := a.stateKey()
		a.history[key] = trimHist(append(a.history[key], HistEntry{Cmd: cmd, Out: strings.TrimRight(out, "\n")}), 40)
		a.refreshTerminal()
		return
	}

	if a.ai == nil {
		a.termLine("  ! Нет API-ключа — открой настройки (кнопка в шапке).")
		a.refreshTerminal()
		return
	}

	task := a.currentTask()
	key := a.stateKey()
	a.busy = true
	a.finishBtn.Disable()
	a.termIn.Disable()
	a.termSpin.Show()
	a.termSpin.Start()

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
		defer cancel()
		res, err := a.ai.RunCommand(ctx, a.cur(), task, a.statePtr(), lastHist(a.history[key], 6), cmd)
		fyne.Do(func() {
			a.termSpin.Hide()
			a.termSpin.Stop()
			a.termIn.SetText("")
			if err != nil {
				a.idleTerminal()
				a.termLine("  ! ошибка симулятора: " + err.Error())
				a.refreshTerminal()
				return
			}
			normalizeState(&res.State)
			a.states[key] = res.State
			out := strings.TrimRight(res.Output, "\n")
			if strings.TrimSpace(out) != "" {
				a.termLine(out)
			}
			a.history[key] = trimHist(append(a.history[key], HistEntry{Cmd: cmd, Out: out}), 40)
			a.refreshTerminal()
			if task != nil && task.Kind == taskQuiz && res.Solved {
				a.verifyTask(task)
				return
			}
			a.idleTerminal()
		})
	}()
}

func (a *App) idleTerminal() {
	a.busy = false
	a.termIn.Enable()
	a.finishBtn.Enable()
	if !a.mobile {
		a.win.Canvas().Focus(a.termIn)
	}
}

func (a *App) currentTask() *Task {
	if a.exam != nil && a.exam.Active {
		if a.exam.Idx < len(a.exam.Tasks) {
			return &a.exam.Tasks[a.exam.Idx]
		}
		return nil
	}
	tasks := a.cur().Tasks
	if a.viewIdx >= 0 && a.viewIdx < len(tasks) {
		return &tasks[a.viewIdx]
	}
	return nil
}

// ---------- проверка и завершение ----------

func (a *App) onFinishTask() {
	if a.busy || a.mentorBusy {
		return
	}
	task := a.currentTask()
	if task == nil {
		a.mentorSay("system", "Активной задачи нет — создай свою через «Задача от ИИ».")
		return
	}
	if a.ai == nil {
		a.mentorSay("system", "Нет API-ключа — открой настройки (кнопка в шапке).")
		return
	}
	if len(task.Quiz) > 0 && !a.quizDone(task.ID) && !a.completed()[task.ID] {
		a.mentorSay("system", "Сначала пройди тест по теории — он в панели задачи.")
		a.switchTab("theory")
		return
	}
	if (a.exam == nil || !a.exam.Active) && a.reviewKey == "" && a.completed()[task.ID] {
		a.mentorSay("system", "Эта задача уже решена. Выбери другую в списке или создай новую.")
		return
	}
	a.busy = true
	a.finishBtn.Disable()
	a.termIn.Disable()
	a.termSpin.Show()
	a.termSpin.Start()
	a.verifyTask(task)
}

func (a *App) verifyTask(task *Task) {
	a.switchTab("terminal")
	a.termLine("  …проверяю выполнение по истории терминала")
	a.refreshTerminal()
	key := a.stateKey()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
		defer cancel()
		res, err := a.ai.Verify(ctx, a.cur(), task, a.statePtr(), lastHist(a.history[key], 12))
		fyne.Do(func() {
			a.termSpin.Hide()
			a.termSpin.Stop()
			if err != nil {
				a.idleTerminal()
				a.termLine("  ! проверка не удалась: " + err.Error())
				a.refreshTerminal()
				a.resultDialog("Проверка не удалась", err.Error(), false)
				return
			}
			inExam := a.exam != nil && a.exam.Active
			if res.Solved {
				switch {
				case inExam:
					a.exam.Results = append(a.exam.Results, true)
					a.termLine("  ✓ засчитано")
					a.refreshTerminal()
					a.examNext()
				case a.reviewKey != "":
					if b := a.prog.Bookmarks[a.reviewKey]; b != nil {
						b.Interval = clamp(b.Interval*2, 2, 30)
						b.Due = time.Now().AddDate(0, 0, b.Interval).Format("2006-01-02")
						b.History = append([]HistEntry(nil), a.history[key]...)
						a.termLine(fmt.Sprintf("  ✓ повтор засчитан — следующее через %d дн. (%s)", b.Interval, b.Due))
						a.saveProgress()
					}
					a.grant("review1")
					a.reviewKey = ""
					a.refreshTerminal()
					a.idleTerminal()
					a.renderTaskPanel()
				default:
					a.completeTask(task, res.Comment, res.Difficulty)
				}
			} else {
				switch {
				case inExam:
					a.exam.Results = append(a.exam.Results, false)
					a.termLine("  ✗ не засчитано: " + res.Comment)
					a.refreshTerminal()
					a.examNext()
				case a.reviewKey != "":
					if b := a.prog.Bookmarks[a.reviewKey]; b != nil {
						b.Interval = 1
						b.Due = time.Now().AddDate(0, 0, 1).Format("2006-01-02")
						a.termLine("  ✗ повтор не зачтён — интервал сброшен, вернёмся завтра")
						a.saveProgress()
					}
					a.reviewKey = ""
					a.refreshTerminal()
					a.idleTerminal()
					a.renderTaskPanel()
				default:
					a.idleTerminal()
					a.termLine("  ✗ пока не выполнено: " + res.Comment)
					a.refreshTerminal()
					a.resultDialog("Пока не выполнено", res.Comment, false)
				}
			}
		})
	}()
}

func (a *App) completeTask(t *Task, note string, checkerDiff int) {
	if a.completed()[t.ID] {
		a.idleTerminal()
		return
	}
	diff := clamp(t.Difficulty, 1, 5)
	if checkerDiff >= 1 && checkerDiff <= 5 {
		diff = checkerDiff
		t.Difficulty = diff
	}
	xp := 15*diff + 15
	a.completed()[t.ID] = true
	a.prog.XP += xp
	a.prog.DiffCount[fmt.Sprintf("d%d", diff)]++
	a.bumpStats()

	if diff == 5 {
		a.grant("hard5")
	}
	a.checkProgressAchievements()

	key := a.cur().ID + "|" + t.ID
	if bm := a.prog.Bookmarks[key]; bm != nil {
		bm.History = append([]HistEntry(nil), a.history[a.cur().ID]...)
	}

	a.saveProgress()
	a.termLine(fmt.Sprintf("  ✓ решено: %s (+%d XP, сложность %d/5)", t.Title, xp, diff))
	if note != "" {
		a.termLine("  " + note)
	}
	wasFrontier := a.viewIdx == a.frontier
	a.recomputeFrontier()
	a.refreshHeader()
	a.refreshList()
	a.idleTerminal()

	msg := fmt.Sprintf("+%d XP → %d XP · уровень %d", xp, a.prog.XP, a.prog.XP/100+1)
	if wasFrontier {
		if a.frontier < len(a.cur().Tasks) {
			a.termLine("")
			a.refreshTerminal()
			a.selectTask(a.frontier, true)
			a.switchTab("theory")
			a.resultDialog("Решено!", msg, true)
		} else {
			a.states[a.cur().ID] = baseState()
			a.stateTask[a.cur().ID] = ""
			a.termLine("")
			a.termLine("  …ИИ пишет следующую задачу по программе курса")
			a.refreshTerminal()
			a.genNextTask(true)
		}
	} else {
		a.renderTaskPanel()
		a.resultDialog("Решено!", msg, true)
	}
}

func (a *App) bumpStats() {
	t := todayStr()
	switch a.prog.LastDay {
	case t:
	case prevDayStr(t):
		a.prog.Streak++
	default:
		a.prog.Streak = 1
	}
	a.prog.LastDay = t
	a.prog.SolvedTotal++
}

func (a *App) resultDialog(title, text string, ok bool) {
	head := canvas.NewText(title, colGood)
	if !ok {
		head.Color = colWarn
	}
	head.TextSize = 18
	head.TextStyle = fyne.TextStyle{Bold: true}
	body := widget.NewLabel(text)
	body.Wrapping = fyne.TextWrapWord
	content := container.NewVBox(head, spacerV(12), body)
	d := dialog.NewCustom(title, "Понятно", content, a.win)
	d.Resize(fyne.NewSize(520, 320))
	d.Show()
}

// ---------- экзамен ----------

func (a *App) startExam() {
	if a.exam != nil && a.exam.Active {
		dialog.ShowInformation("Экзамен", "Экзамен уже идёт — заверши его.", a.win)
		return
	}
	if a.ai == nil {
		a.mentorSay("system", "Нет API-ключа — открой настройки и настрой ИИ-провайдера и ключ.")
		return
	}
	dialog.NewCustomConfirm("Экзамен", "Начать", "Отмена",
		widget.NewLabel("ИИ соберёт 5 задач по пройденному материалу текущего курса.\nПосле каждой — проверка. Подсказок не будет.\nВ конце — оценка и бонус: +10 XP за каждую верную задачу."),
		func(ok bool) {
			if !ok {
				return
			}
			c := a.cur()
			courseTitle := c.Title
			recent := recentTitles(c, 8)
			a.busy = true
			a.examBtn.Disable()
			go func() {
				ex := &ExamSession{Started: time.Now()}
				for i := 0; i < 5; i++ {
					n := i + 1
					fyne.Do(func() {
						a.termLine(fmt.Sprintf("  …экзамен: генерирую задачу %d/5", n))
						a.refreshTerminal()
					})
					tctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
					t, err := a.ai.GenerateTask(tctx, courseTitle,
						"повторение пройденного — выбери сам подходящую тему курса (можно cmd или quiz)", recent, "")
					cancel()
					if err != nil {
						fyne.Do(func() {
							a.busy = false
							a.examBtn.Enable()
							a.termLine("  ! экзамен отменён: " + err.Error())
							a.refreshTerminal()
						})
						return
					}
					ex.Tasks = append(ex.Tasks, *t)
				}
				fyne.Do(func() {
					a.busy = false
					a.examBtn.Enable()
					ex.Active = true
					a.exam = ex
					a.termLine("")
					a.termLine("── ЭКЗАМЕН: 5 задач ──")
					a.refreshTerminal()
					a.examLoad()
					a.idleTerminal()
				})
			}()
		}, a.win).Show()
}

func (a *App) examLoad() {
	ex := a.exam
	t := &ex.Tasks[ex.Idx]
	normalizeState(&t.Start)
	a.states[examKey] = cloneState(t.Start)
	a.history[examKey] = nil
	a.termLine(fmt.Sprintf("Вопрос %d/5: %s", ex.Idx+1, t.Title))
	a.termLine("  " + t.Goal)
	a.refreshTerminal()
	a.renderTaskPanel()
	a.switchTab("theory")
}

func (a *App) examNext() {
	ex := a.exam
	ex.Idx++
	if ex.Idx >= len(ex.Tasks) {
		a.finishExam()
		return
	}
	a.examLoad()
	a.idleTerminal()
}

func (a *App) finishExam() {
	ex := a.exam
	score := 0
	for _, ok := range ex.Results {
		if ok {
			score++
		}
	}
	elapsed := time.Since(ex.Started).Round(time.Second)
	bonus := score * 10
	a.prog.XP += bonus
	a.saveProgress()
	a.refreshHeader()
	a.exam = nil
	a.idleTerminal()

	a.termLine(fmt.Sprintf("── Экзамен завершён: %d/5 за %v · бонус +%d XP ──", score, elapsed, bonus))
	a.refreshTerminal()

	if score >= 4 {
		a.grant("exam-good")
	}
	if score == 5 {
		a.grant("exam-perfect")
	}

	grade := "2 — нужно повторить тему"
	switch {
	case score == 5:
		grade = "5 — отлично!"
	case score == 4:
		grade = "4 — хорошо"
	case score == 3:
		grade = "3 — удовлетворительно"
	}
	a.resultDialog("Результат экзамена",
		fmt.Sprintf("Оценка: %s\nВерных задач: %d из 5\nВремя: %v\nБонус: +%d XP", grade, score, elapsed, bonus),
		score >= 3)
	a.selectTask(a.frontier, true)
	a.renderTaskPanel()
}

// ---------- пересборка курса ----------

func (a *App) openRebuildDialog() {
	if a.busy {
		return
	}
	if a.exam != nil && a.exam.Active {
		a.mentorSay("system", "Сначала заверши экзамен.")
		return
	}
	instr := widget.NewMultiLineEntry()
	instr.SetPlaceHolder("например: «теория с примерами команд в блоках кода, задачи ближе к реальной работе, тесты посложнее»")
	content := container.NewVBox(
		widget.NewLabel("ИИ заново создаст все НЕпройденные задачи текущего курса\nпо твоему указанию. Решённые задачи останутся как есть."),
		spacerV(8),
		widget.NewLabel("Как переделать задачи:"),
		instr,
	)
	dialog.NewCustomConfirm("Пересобрать курс", "Пересобрать", "Отмена", content, func(ok bool) {
		if !ok {
			return
		}
		a.rebuildCourse(strings.TrimSpace(instr.Text))
	}, a.win).Show()
}

func (a *App) rebuildCourse(instr string) {
	if a.busy {
		return
	}
	if a.ai == nil {
		a.mentorSay("system", "Нет API-ключа — открой настройки и настрой ИИ-провайдера и ключ.")
		return
	}
	c := a.cur()
	cid := c.ID
	done := make(map[string]bool, len(a.completed()))
	for k, v := range a.completed() {
		done[k] = v
	}
	total := 0
	for i := range c.Tasks {
		if !done[c.Tasks[i].ID] {
			total++
		}
	}
	if total == 0 {
		a.mentorSay("system", "Все задачи курса решены — пересобирать нечего. Создай новую через «Задача от ИИ».")
		return
	}

	a.busy = true
	a.rebuildBtn.Disable()
	a.termLine(fmt.Sprintf("  …пересобираю курс «%s»: %d задач. Указание: %s", c.Title, total, instr))
	a.refreshTerminal()

	go func() {
		type rep struct {
			idx int
			t   Task
		}
		var reps []rep
		failed := ""
		for i := range c.Tasks {
			if done[c.Tasks[i].ID] {
				continue
			}
			topic := ""
			if i < len(c.Syllabus) {
				topic = c.Syllabus[i]
			} else {
				topic = "повторение пройденного — выбери тему сам"
			}
			tctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
			t, err := a.ai.GenerateTask(tctx, c.Title, topic, recentTitles(c, 8), instr)
			cancel()
			if err != nil {
				failed = err.Error()
				break
			}
			reps = append(reps, rep{i, *t})
			nn := len(reps)
			idx := i
			fyne.Do(func() {
				a.termLine(fmt.Sprintf("  ✓ задача %d пересобрана (%d/%d)", idx+1, nn, total))
				a.refreshTerminal()
			})
		}
		fyne.Do(func() {
			for _, r := range reps {
				c.Tasks[r.idx] = r.t
				if a.prog.Overrides[cid] == nil {
					a.prog.Overrides[cid] = map[int]Task{}
				}
				a.prog.Overrides[cid][r.idx] = r.t
			}
			a.saveProgress()
			a.busy = false
			a.rebuildBtn.Enable()
			a.tasksOf(c)
			delete(a.states, cid)
			a.stateTask[cid] = ""
			a.recomputeFrontier()
			a.resetCourseState()
			a.refreshList()
			if failed != "" {
				a.termLine("  ! пересборка прервана: " + failed)
			}
			a.termLine(fmt.Sprintf("  ✓ готово: пересобрано задач — %d", len(reps)))
			a.refreshTerminal()
			if len(reps) > 0 {
				a.grant("rebuilder")
			}
			a.selectTask(a.frontier, true)
			a.renderTaskPanel()
			a.resultDialog("Пересборка", fmt.Sprintf("Пересобрано задач: %d из %d.", len(reps), total), failed == "")
		})
	}()
}

// ---------- файлы песочницы ----------

func (a *App) showFiles() {
	files := a.state().Files
	content := container.NewVBox()
	if len(files) == 0 {
		content.Add(widget.NewLabel("Файлов в песочнице нет."))
	} else {
		names := make([]string, 0, len(files))
		for n := range files {
			names = append(names, n)
		}
		sort.Strings(names)
		preview := widget.NewMultiLineEntry()
		preview.TextStyle = fyne.TextStyle{Monospace: true}
		preview.Wrapping = fyne.TextWrapWord
		current := ""
		preview.OnChanged = func(s string) {
			if s != current {
				preview.SetText(current)
			}
		}
		previewBox := container.NewStack(canvas.NewRectangle(colTerm),
			container.NewPadded(fixedHeight(240, container.NewScroll(preview))))
		for _, n := range names {
			name, body := n, files[n]
			content.Add(widget.NewButton(name, func() {
				current = body
				preview.SetText(body)
			}))
		}
		content.Add(spacerV(10))
		content.Add(previewBox)
		current = files[names[0]]
		preview.SetText(files[names[0]])
	}
	d := dialog.NewCustom("Файлы песочницы", "Закрыть", content, a.win)
	d.Resize(fyne.NewSize(620, 460))
	d.Show()
}

// ---------- статистика ----------

func (a *App) showStats() {
	done := a.completed()
	solvedCourse := 0
	for _, v := range done {
		if v {
			solvedCourse++
		}
	}
	overdue := 0
	today := todayStr()
	for _, b := range a.prog.Bookmarks {
		if b.Due <= today {
			overdue++
		}
	}
	aiTasks := 0
	for _, ts := range a.prog.Generated {
		aiTasks += len(ts)
	}
	rebuilt := 0
	for _, m := range a.prog.Overrides {
		rebuilt += len(m)
	}
	var diffs []string
	for d := 1; d <= 5; d++ {
		diffs = append(diffs, fmt.Sprintf("%d★:%d", d, a.prog.DiffCount[fmt.Sprintf("d%d", d)]))
	}
	inner := container.NewVBox(
		widget.NewLabel(fmt.Sprintf("Уровень %d · %d XP", a.prog.XP/100+1, a.prog.XP)),
		widget.NewLabel(fmt.Sprintf("Всего решено задач: %d", a.prog.SolvedTotal)),
		widget.NewLabel(fmt.Sprintf("Серия: %d дн. подряд", a.prog.Streak)),
		widget.NewLabel(fmt.Sprintf("Время сегодня: %s · всего: %s", formatDuration(a.prog.TimeSeconds[today]), formatDuration(totalSeconds(a.prog.TimeSeconds)))),
		widget.NewLabel(fmt.Sprintf("Курс «%s»: решено %d из %d", a.cur().Title, solvedCourse, len(a.cur().Tasks))),
		widget.NewLabel("По сложностям: "+strings.Join(diffs, "  ")),
		widget.NewLabel(fmt.Sprintf("Закладки: %d (к повтору сегодня: %d)", len(a.prog.Bookmarks), overdue)),
		widget.NewLabel(fmt.Sprintf("Задач от ИИ: %d · курсов от ИИ: %d · пересобрано: %d", aiTasks, len(a.prog.Extra), rebuilt)),
		spacerV(12),
		caption("ДОСТИЖЕНИЯ", colAccent),
		spacerV(4),
	)
	for _, line := range achievementLines(a.prog) {
		inner.Add(widget.NewLabel(line))
	}
	content := container.NewScroll(inner)
	d := dialog.NewCustom("Статистика", "Закрыть", content, a.win)
	d.Resize(fyne.NewSize(540, 580))
	d.Show()
}

// ---------- закладки и интервальное повторение ----------

func (a *App) toggleBookmark() {
	tasks := a.cur().Tasks
	if a.viewIdx < 0 || a.viewIdx >= len(tasks) {
		return
	}
	t := &tasks[a.viewIdx]
	key := a.cur().ID + "|" + t.ID
	if _, ok := a.prog.Bookmarks[key]; ok {
		delete(a.prog.Bookmarks, key)
		a.mentorSay("system", "Закладка снята.")
	} else {
		a.prog.Bookmarks[key] = &Bookmark{
			TaskID:   t.ID,
			CourseID: a.cur().ID,
			Interval: 1,
			Due:      todayStr(),
			History:  append([]HistEntry(nil), a.history[a.cur().ID]...),
		}
		a.mentorSay("system", "Добавлено в закладки. Кнопка «Повторение» — посмотреть задачу, свою историю и попросить меня объяснить.")
	}
	a.saveProgress()
	a.renderTaskPanel()
}

func (a *App) findBookmarkTask(k string) (int, int, *Bookmark, bool) {
	b := a.prog.Bookmarks[k]
	if b == nil {
		return 0, 0, nil, false
	}
	for ci := range a.courses {
		if a.courses[ci].ID != b.CourseID {
			continue
		}
		for ti := range a.courses[ci].Tasks {
			if a.courses[ci].Tasks[ti].ID == b.TaskID {
				return ci, ti, b, true
			}
		}
	}
	return 0, 0, nil, false
}

func (a *App) showReview() {
	if a.exam != nil && a.exam.Active {
		dialog.ShowInformation("Повторение", "Сначала заверши экзамен.", a.win)
		return
	}
	var keys []string
	for k := range a.prog.Bookmarks {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var d dialog.Dialog
	content := container.NewVBox()
	today := todayStr()
	for _, k := range keys {
		ci, ti, b, ok := a.findBookmarkTask(k)
		if !ok {
			continue
		}
		when := "к повтору сегодня"
		if b.Due > today {
			when = "через " + fmt.Sprint(daysBetween(today, b.Due)) + " дн."
		}
		label := a.courses[ci].Title + " — " + a.courses[ci].Tasks[ti].Title + "  (" + when + ")"
		kk := k
		content.Add(widget.NewButton(label, func() {
			d.Hide()
			a.showBookmarkDetail(kk)
		}))
	}
	if len(content.Objects) == 0 {
		content.Add(widget.NewLabel("Закладок пока нет.\nДобавляй задачи кнопкой ☆ в панели задачи —\nпотом их можно повторять и разбирать со мной."))
	}
	d = dialog.NewCustom("Закладки и повторение", "Закрыть", content, a.win)
	d.Resize(fyne.NewSize(560, 420))
	d.Show()
}

func (a *App) showBookmarkDetail(k string) {
	ci, ti, b, ok := a.findBookmarkTask(k)
	if !ok {
		a.mentorSay("system", "Закладка устарела — задачи больше нет. Удаляю.")
		delete(a.prog.Bookmarks, k)
		a.saveProgress()
		return
	}
	task := &a.courses[ci].Tasks[ti]
	courseTitle := a.courses[ci].Title

	var histStr string
	if len(b.History) == 0 {
		histStr = "(история пуста — задача ещё не решалась после добавления)"
	} else {
		var sb strings.Builder
		for _, h := range b.History {
			out := h.Out
			if len(out) > 400 {
				out = out[:400] + "…"
			}
			sb.WriteString("$ " + h.Cmd + "\n" + out + "\n\n")
		}
		histStr = sb.String()
	}

	content := container.NewVBox(
		widget.NewLabel("Курс: "+courseTitle),
		accentGoal(task.Goal),
		spacerV(10),
		widget.NewLabel("Как ты решал:"),
		container.NewStack(canvas.NewRectangle(colTerm),
			container.NewPadded(fixedHeight(220, container.NewScroll(readOnlyView(histStr, true))))),
		spacerV(10),
		container.NewGridWithColumns(2,
			widget.NewButton("Повторить сейчас", func() { a.reviewFromBookmark(ci, ti, k) }),
			widget.NewButton("Спросить ментора", func() { a.explainFromBookmark(ci, ti, task.Title) }),
		),
		widget.NewButton("Убрать из закладок", func() {
			delete(a.prog.Bookmarks, k)
			a.saveProgress()
			a.mentorSay("system", "Закладка удалена.")
		}),
	)
	d := dialog.NewCustom("Закладка: "+task.Title, "Закрыть", content, a.win)
	d.Resize(fyne.NewSize(640, 560))
	d.Show()
}

func readOnlyView(text string, mono bool) *widget.Entry {
	e := widget.NewMultiLineEntry()
	if mono {
		e.TextStyle = fyne.TextStyle{Monospace: true}
	}
	e.Wrapping = fyne.TextWrapWord
	e.SetText(text)
	e.OnChanged = func(s string) {
		if s != text {
			e.SetText(text)
		}
	}
	return e
}

func (a *App) reviewFromBookmark(ci, ti int, k string) {
	if a.exam != nil && a.exam.Active {
		a.mentorSay("system", "Сначала заверши экзамен.")
		return
	}
	if ci != a.courseIdx {
		a.switchCourse(ci)
	}
	a.reviewKey = k
	a.selectTask(ti, true)
	a.switchTab("theory")
	a.mentorSay("system", "Режим повторения: пройди тест (если не пройден) и выполни задачу, затем «Завершить задачу».")
}

func (a *App) explainFromBookmark(ci, ti int, title string) {
	if ci != a.courseIdx {
		a.switchCourse(ci)
	}
	a.reviewKey = ""
	a.selectTask(ti, false)
	q := fmt.Sprintf("Объясни задачу «%s»: что требуется, на что обратить внимание и в каком порядке действовать. Не давай сразу готовые команды — сначала идея.", title)
	a.sendChatText(q)
	a.switchTab("theory")
}

// ---------- генерация задач и курсов ----------

func recentTitles(c *Course, n int) []string {
	out := make([]string, 0, n)
	for i := 0; i < len(c.Tasks) && i < n; i++ {
		out = append(out, c.Tasks[len(c.Tasks)-1-i].Title)
	}
	return out
}

func (a *App) openTaskDialog() {
	if a.exam != nil && a.exam.Active {
		a.mentorSay("system", "Сначала заверши экзамен.")
		return
	}
	topic := widget.NewEntry()
	topic.PlaceHolder = "тема или описание: напр. «проброс портов» или «задача как на работе: задеплоить контейнер»"
	content := container.NewVBox(
		widget.NewLabel("Опиши задачу — ИИ сгенерирует её (теория + тест + практика)\nи добавит в текущий курс. Можно любую тему:"),
		topic,
	)
	dialog.NewCustomConfirm("Новая задача от ИИ", "Создать", "Отмена", content, func(ok bool) {
		if !ok {
			return
		}
		g := strings.TrimSpace(topic.Text)
		if g == "" {
			return
		}
		a.generateTaskWithTopic(g)
	}, a.win).Show()
}

func (a *App) generateTaskWithTopic(topic string) {
	if a.busy {
		return
	}
	if a.ai == nil {
		a.mentorSay("system", "Нет API-ключа — открой настройки и настрой ИИ-провайдера и ключ.")
		return
	}
	c := a.cur()
	a.busy = true
	a.genBtn.Disable()
	a.genSpin.Show()
	a.genSpin.Start()
	a.termLine("  …ИИ пишет задачу по теме: " + topic)
	a.refreshTerminal()

	done := recentTitles(c, 10)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
		defer cancel()
		t, err := a.ai.GenerateTask(ctx, c.Title, topic, done, "")
		fyne.Do(func() {
			a.busy = false
			a.genSpin.Hide()
			a.genSpin.Stop()
			a.genBtn.Enable()
			if err != nil {
				a.termLine("  ! не удалось сгенерировать задачу: " + err.Error())
				a.refreshTerminal()
				a.mentorSay("system", "Генерация не удалась: "+err.Error()+". Попробуй ещё раз.")
				return
			}
			c.Tasks = append(c.Tasks, *t)
			a.prog.Generated[c.ID] = append(a.prog.Generated[c.ID], *t)
			a.saveProgress()
			a.recomputeFrontier()
			a.refreshList()
			a.grant("author")
			a.termLine("")
			a.termLine("  + новая задача добавлена: " + t.Title)
			a.refreshTerminal()
			a.selectTask(len(c.Tasks)-1, true)
			a.switchTab("theory")
		})
	}()
}

func (a *App) genNextTask(auto bool) {
	if a.busy {
		return
	}
	if a.exam != nil && a.exam.Active {
		return
	}
	if a.ai == nil {
		a.mentorSay("system", "Нет API-ключа — открой настройки и настрой ИИ-провайдера и ключ.")
		return
	}
	c := a.cur()
	topic := ""
	if len(c.Tasks) < len(c.Syllabus) {
		topic = c.Syllabus[len(c.Tasks)]
	} else {
		topic = "повторение пройденного — выбери подходящую тему сам (можно cmd или quiz)"
	}

	a.busy = true
	a.genBtn.Disable()
	a.genSpin.Show()
	a.genSpin.Start()
	a.termLine("  …ИИ пишет следующую задачу по программе курса")
	a.refreshTerminal()

	done := recentTitles(c, 10)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
		defer cancel()
		t, err := a.ai.GenerateTask(ctx, c.Title, topic, done, "")
		fyne.Do(func() {
			a.busy = false
			a.genSpin.Hide()
			a.genSpin.Stop()
			a.genBtn.Enable()
			if err != nil {
				a.termLine("  ! не удалось сгенерировать задачу: " + err.Error())
				a.refreshTerminal()
				a.mentorSay("system", "Генерация не удалась: "+err.Error()+". Жми «Задача от ИИ», чтобы повторить.")
				return
			}
			c.Tasks = append(c.Tasks, *t)
			a.prog.Generated[c.ID] = append(a.prog.Generated[c.ID], *t)
			a.saveProgress()
			a.recomputeFrontier()
			a.refreshList()
			a.termLine("")
			a.refreshTerminal()
			a.selectTask(a.frontier, true)
			a.switchTab("theory")
		})
	}()
}

func (a *App) openNewCourseDialog() {
	if a.exam != nil && a.exam.Active {
		a.mentorSay("system", "Сначала заверши экзамен.")
		return
	}
	goal := widget.NewEntry()
	goal.PlaceHolder = "например: хочу стать девопс-инженером"
	content := container.NewVBox(
		widget.NewLabel("Опиши цель — ИИ соберёт программу из нескольких курсов\n(практика с командами + тесты, включая смежные темы: сети и т.д.):"),
		goal,
	)
	dialog.NewCustomConfirm("Новый курс от ИИ", "Создать", "Отмена", content, func(ok bool) {
		if !ok {
			return
		}
		g := strings.TrimSpace(goal.Text)
		if g == "" {
			return
		}
		if a.ai == nil {
			a.mentorSay("system", "Нет API-ключа — открой настройки и настрой ИИ-провайдера и ключ.")
			return
		}
		a.busy = true
		a.aiCourseBtn.Disable()
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 240*time.Second)
			defer cancel()
			news, err := a.ai.GenerateCourses(ctx, g)
			fyne.Do(func() {
				a.busy = false
				a.aiCourseBtn.Enable()
				if err != nil || len(news) == 0 {
					a.mentorSay("system", "Не удалось создать курс: "+fmt.Sprint(err))
					return
				}
				a.courses = append(a.courses, news...)
				a.prog.Extra = append(a.prog.Extra, news...)
				a.saveProgress()
				a.refreshCourseOptions()
				a.grant("architect")
				names := make([]string, len(news))
				for i := range news {
					names[i] = news[i].Title
				}
				a.mentorSay("mentor", "Собрал программу: "+strings.Join(names, " → ")+". Начинаем с первого — задачи будут появляться по ходу. Курсы сохранены между сеансами.")
				for i := range a.courses {
					if a.courses[i].ID == news[0].ID {
						a.switchCourse(i)
						break
					}
				}
			})
		}()
	}, a.win).Show()
}

// ---------- навигация (свободный выбор задач) ----------

func (a *App) selectTask(i int, highlight bool) {
	a.viewIdx = i
	if highlight && i >= 0 && i < len(a.cur().Tasks) {
		a.list.Select(widget.ListItemID(i))
	}
	a.renderTaskPanel()
	if i >= 0 && i < len(a.cur().Tasks) {
		a.ensureStateForTask(&a.cur().Tasks[i])
	}
}

func (a *App) onTaskClicked(i int) {
	tasks := a.cur().Tasks
	if i < 0 || i >= len(tasks) {
		return
	}
	a.viewIdx = i
	a.reviewKey = ""
	a.renderTaskPanel()
	a.ensureStateForTask(&tasks[i])
	a.switchTab("theory")
}

func (a *App) refreshHeader() {
	a.xpText.Text = fmt.Sprintf("уровень %d · %d XP · серия %d дн.", a.prog.XP/100+1, a.prog.XP, a.prog.Streak)
	a.xpText.Refresh()
}

// ---------- таймер времени ----------

func (a *App) startTimer() {
	go func() {
		second := time.NewTicker(time.Second)
		save := time.NewTicker(30 * time.Second)
		defer second.Stop()
		defer save.Stop()
		for {
			select {
			case <-second.C:
				a.tickSecond()
			case <-save.C:
				fyne.Do(func() { a.saveProgress() })
			}
		}
	}()
}

func (a *App) tickSecond() {
	fyne.Do(func() {
		a.prog.TimeSeconds[todayStr()]++
		a.refreshTimer()
	})
}

func (a *App) refreshTimer() {
	a.timerText.Text = " · ⏱ " + formatDuration(a.prog.TimeSeconds[todayStr()])
	a.timerText.Refresh()
}

func formatDuration(sec int) string {
	h := sec / 3600
	m := (sec % 3600) / 60
	s := sec % 60
	if h > 0 {
		return fmt.Sprintf("%d:%02d:%02d", h, m, s)
	}
	return fmt.Sprintf("%d:%02d", m, s)
}

func totalSeconds(m map[string]int) int {
	total := 0
	for _, v := range m {
		total += v
	}
	return total
}

// ---------- markdown → обычный текст (чат ментора) ----------

func mdToPlain(md string) string {
	lines := strings.Split(strings.ReplaceAll(md, "\r\n", "\n"), "\n")
	out := make([]string, 0, len(lines))
	inCode := false
	for _, ln := range lines {
		tr := strings.TrimSpace(ln)
		if strings.HasPrefix(tr, "```") {
			inCode = !inCode
			continue
		}
		if inCode {
			out = append(out, "    "+ln)
			continue
		}
		switch {
		case tr == "":
			out = append(out, "")
		case strings.HasPrefix(tr, "#"):
			out = append(out, strings.TrimLeft(tr, "# "))
		case strings.HasPrefix(tr, "- "), strings.HasPrefix(tr, "* "):
			out = append(out, "•  "+tr[2:])
		default:
			out = append(out, tr)
		}
	}
	s := strings.Join(out, "\n")
	s = strings.ReplaceAll(s, "**", "")
	s = strings.ReplaceAll(s, "`", "")
	return s
}

// ---------- ментор ----------

func (a *App) mentorSay(role, text string) {
	switch role {
	case "mentor":
		a.chatText += "Наставник:\n" + mdToPlain(text) + "\n\n"
	case "system":
		a.chatText += "· " + text + "\n\n"
	default:
		a.chatText += "Ты:\n" + text + "\n\n"
	}
	a.chatOut.SetText(a.chatText)
	a.chatOut.Refresh()
	a.scrollChatBottom()
}

// scrollChatBottom — докручивает чат до последнего сообщения (с повтором после
// раскладки, т.к. сразу после SetText высота ещё не пересчитана).
func (a *App) scrollChatBottom() {
	a.chatScroll.ScrollToBottom()
	a.chatScroll.Refresh()
	time.AfterFunc(40*time.Millisecond, func() {
		fyne.Do(func() { a.chatScroll.ScrollToBottom() })
	})
}

func (a *App) sendChat() {
	q := strings.TrimSpace(a.chatIn.Text)
	if q == "" && len(a.attachNames) == 0 {
		return
	}
	a.chatIn.SetText("")
	a.sendChatText(q)
}

func (a *App) sendChatText(q string) {
	if a.mentorBusy {
		return
	}
	if q == "" && len(a.attachNames) == 0 {
		return
	}

	// собираем вложения: текстовые файлы добавляем к вопросу, картинки — отдельно
	question := q
	imgs := append([]string(nil), a.attachImages...)
	if len(a.attachTexts) > 0 {
		if question != "" {
			question += "\n\n"
		}
		question += strings.Join(a.attachTexts, "\n\n")
	}
	a.clearAttachments()

	echo := q
	if echo == "" {
		echo = "(вложение)"
	}
	a.mentorSay("user", echo)
	a.chatLog = trimLast(append(a.chatLog, "Студент: "+echo), 8)

	if a.ai == nil {
		a.mentorSay("system", "Нет API-ключа — открой настройки (кнопка в шапке) и настрой ИИ-провайдера и ключ.")
		return
	}

	a.mentorBusy = true
	a.chatSendBtn.Disable()
	a.chatSpin.Show()
	a.chatSpin.Start()

	key := a.stateKey()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
		defer cancel()
		answer, err := a.ai.Mentor(ctx, a.cur(), a.currentTask(), a.statePtr(),
			lastHist(a.history[key], 8), a.chatLog, question, imgs)
		fyne.Do(func() {
			a.mentorBusy = false
			a.chatSpin.Hide()
			a.chatSpin.Stop()
			a.chatSendBtn.Enable()
			if err != nil {
				a.mentorSay("system", "Наставник недоступен: "+err.Error())
				return
			}
			a.mentorSay("mentor", answer)
			a.chatLog = trimLast(append(a.chatLog, "Наставник: "+answer), 8)
		})
	}()
}

// ---------- вложения в чат ----------

var imageExts = map[string]bool{".png": true, ".jpg": true, ".jpeg": true, ".webp": true, ".gif": true, ".bmp": true}

func (a *App) attachFile() {
	dialog.NewFileOpen(func(r fyne.URIReadCloser, err error) {
		if err != nil || r == nil {
			return
		}
		defer r.Close()
		data, err := io.ReadAll(r)
		if err != nil {
			a.mentorSay("system", "Не удалось прочитать файл: "+err.Error())
			return
		}
		name := r.URI().Name()
		a.handleAttachment(name, data)
	}, a.win).Show()
}

func (a *App) handleAttachment(name string, data []byte) {
	ext := strings.ToLower(filepath.Ext(name))
	if imageExts[ext] {
		if !visionModelSupported(a.cfg.Provider, a.cfg.Model) {
			a.mentorSay("system", "Текущая модель «"+a.cfg.Model+"» не поддерживает изображения. Выбери vision-модель (например gemini-2.0-flash, gpt-4o, qwen-vl-max) — и импорт фото разблокируется.")
			return
		}
		if len(data) > 8*1024*1024 {
			a.mentorSay("system", "Изображение слишком большое (макс. 8 МБ).")
			return
		}
		mime := "image/png"
		switch ext {
		case ".jpg", ".jpeg":
			mime = "image/jpeg"
		case ".webp":
			mime = "image/webp"
		case ".gif":
			mime = "image/gif"
		case ".bmp":
			mime = "image/bmp"
		}
		a.attachImages = append(a.attachImages, "data:"+mime+";base64,"+base64.StdEncoding.EncodeToString(data))
		a.attachNames = append(a.attachNames, name)
	} else {
		if len(data) > 256*1024 {
			a.mentorSay("system", "Текстовый файл слишком большой (макс. 256 КБ).")
			return
		}
		if !utf8Valid(data) {
			a.mentorSay("system", "Файл не похож на текст (бинарный). Поддерживаются только текст и изображения.")
			return
		}
		content := strings.TrimSpace(string(data))
		if content == "" {
			a.mentorSay("system", "Файл пустой.")
			return
		}
		a.attachTexts = append(a.attachTexts, "### файл: "+name+"\n"+content)
		a.attachNames = append(a.attachNames, name)
	}
	a.refreshAttachUI()
}

func utf8Valid(b []byte) bool {
	return strings.ToValidUTF8(string(b), "\uFFFD") == string(b)
}

func (a *App) clearAttachments() {
	a.attachNames = nil
	a.attachTexts = nil
	a.attachImages = nil
	a.refreshAttachUI()
}

func (a *App) refreshAttachUI() {
	if a.attachLabel == nil || a.attachRow == nil {
		return
	}
	if len(a.attachNames) == 0 {
		a.attachLabel.SetText("")
		a.attachRow.Hide()
	} else {
		a.attachLabel.SetText("📎 " + strings.Join(a.attachNames, ", "))
		a.attachRow.Show()
	}
	a.attachLabel.Refresh()
	a.attachRow.Refresh()
}

// ---------- экспорт / импорт прогресса ----------

func (a *App) exportProgress() {
	fd := dialog.NewFileSave(func(f fyne.URIWriteCloser, err error) {
		if err != nil || f == nil {
			return
		}
		data, _ := json.MarshalIndent(a.prog, "", "  ")
		_, werr := f.Write(data)
		f.Close()
		if werr != nil {
			a.mentorSay("system", "Ошибка записи: "+werr.Error())
			return
		}
		dialog.ShowInformation("Экспорт", "Прогресс сохранён: "+f.URI().Name(), a.win)
	}, a.win)
	fd.SetFileName("termai-progress.json")
	fd.Show()
}

func (a *App) importProgress() {
	dialog.NewFileOpen(func(r fyne.URIReadCloser, err error) {
		if err != nil || r == nil {
			return
		}
		defer r.Close()
		data, err := io.ReadAll(r)
		if err != nil {
			a.mentorSay("system", "Не удалось прочитать файл: "+err.Error())
			return
		}
		p := newProgress()
		if err := json.Unmarshal(data, p); err != nil {
			a.mentorSay("system", "Файл не похож на прогресс тренажёра: "+err.Error())
			return
		}
		p.ensure()
		a.prog = p
		a.saveProgress()
		a.reloadFromProgress()
		dialog.ShowInformation("Импорт",
			fmt.Sprintf("Прогресс загружен: %d XP, серия %d дн.", p.XP, p.Streak), a.win)
		a.mentorSay("system", "Прогресс импортирован — курсы, задачи от ИИ и закладки на месте.")
	}, a.win).Show()
}

func (a *App) reloadFromProgress() {
	a.courses = append(builtinCourses(), a.prog.Extra...)
	for i := range a.courses {
		cid := a.courses[i].ID
		a.courses[i].Tasks = append(a.courses[i].Tasks, a.prog.Generated[cid]...)
		for idx, t := range a.prog.Overrides[cid] {
			if idx >= 0 && idx < len(a.courses[i].Tasks) {
				a.courses[i].Tasks[idx] = t
			}
		}
	}
	idx := 0
	for i := range a.courses {
		if a.courses[i].ID == a.prog.LastCourse {
			idx = i
		}
	}
	a.courseIdx = idx
	a.tasksOf(a.cur())
	a.states = map[string]SandboxState{}
	a.history = map[string][]HistEntry{}
	a.stateTask = map[string]string{}
	a.exam = nil
	a.reviewKey = ""
	a.recomputeFrontier()
	a.resetCourseState()
	a.refreshCourseOptions()
	a.courseSel.SetSelected(a.cur().Title)
	a.refreshList()
	a.refreshHeader()
	a.selectTask(a.frontier, true)
	a.renderTaskPanel()
}

// ---------- настройки ----------

func (a *App) openSettings() {
	key := widget.NewPasswordEntry()
	key.PlaceHolder = "sk-…"
	key.SetText(a.cfg.APIKey)

	// провайдер ИИ
	provSel := widget.NewSelect(providerTitles(), nil)
	provSel.PlaceHolder = "провайдер"
	provSel.SetSelected(findProvider(a.cfg.Provider).Title)

	modelSel := widget.NewSelect(nil, nil)
	modelSel.PlaceHolder = "модель"

	customModel := widget.NewEntry()
	customModel.PlaceHolder = "своя модель (перекроет список)"

	baseURL := widget.NewEntry()
	baseURL.PlaceHolder = "base URL (пусто — из пресета провайдера)"
	baseURL.SetText(a.cfg.BaseURL)

	cur := findProvider(a.cfg.Provider)
	modelSel.Options = cur.Models
	modelSel.Refresh()
	if a.cfg.Model != "" && hasString(cur.Models, a.cfg.Model) {
		modelSel.SetSelected(a.cfg.Model)
	}
	if a.cfg.Model != "" && !hasString(cur.Models, a.cfg.Model) {
		customModel.SetText(a.cfg.Model)
	}

	provSel.OnChanged = func(title string) {
		p := findProvider(providerIDByTitle(title))
		baseURL.SetText(p.BaseURL)
		modelSel.Options = p.Models
		modelSel.Refresh()
		modelSel.SetSelected(p.DefaultModel)
		customModel.SetText("")
	}

	fontPath := widget.NewEntry()
	fontPath.PlaceHolder = "например, /usr/share/fonts/TiemposText-Regular.ttf"
	fontPath.SetText(a.cfg.FontPath)

	// хоткеи
	a.hotkeyBtns = map[string]*widget.Button{}
	hkRows := container.NewVBox()
	for _, def := range hotkeyDefs {
		def := def
		btn := widget.NewButton(a.hotkeyFor(def.Action), nil)
		a.hotkeyBtns[def.Action] = btn
		btn.OnTapped = func() { a.captureHotkey(def.Action, btn) }
		hkRows.Add(container.NewBorder(nil, nil, widget.NewLabel(def.Title), btn))
	}
	resetHotkeysBtn := widget.NewButton("Сбросить клавиши к стандартным", func() {
		a.cfg.Hotkeys = map[string]string{}
		_ = saveConfig(a.cfg)
		for _, def := range hotkeyDefs {
			a.hotkeyBtns[def.Action].SetText(a.hotkeyFor(def.Action))
			a.hotkeyBtns[def.Action].Refresh()
		}
		dialog.ShowInformation("Горячие клавиши", "Стандартные комбинации полностью восстановятся после перезапуска.", a.win)
	})

	// whisper
	wbin := widget.NewEntry()
	wbin.PlaceHolder = "путь к whisper-cli (пусто — искать в PATH и ~/whisper.cpp/build/bin)"
	wbin.SetText(a.cfg.WhisperBin)
	wmodel := widget.NewEntry()
	wmodel.PlaceHolder = "путь к модели ggml-*.bin"
	wmodel.SetText(a.cfg.WhisperModel)
	dlBtn := widget.NewButton("Скачать модель ggml-base (~148 МБ)", func() { a.downloadWhisperModel(wmodel) })

	hold := newHoldButton(
		func() {
			dialog.ShowInformation("Сброс прогресса",
				"Удерживай кнопку 5 секунд для подтверждения.", a.win)
		},
		a.resetAllProgress)

	inner := container.NewVBox(
		caption("ИИ-ПРОВАЙДЕР", colAccent), spacerV(4),
		widget.NewLabel("Провайдер:"), provSel,
		widget.NewLabel("API-ключ:"), key,
		widget.NewLabel("Модель:"), modelSel, customModel,
		widget.NewLabel("Base URL (endpoint):"), baseURL,
		widget.NewLabel("DeepSeek, OpenAI, Gemini, Qwen, OpenRouter, Groq, Mistral, локальный Ollama\nили свой OpenAI-совместимый endpoint. Для Ollama ключ не нужен."),
		spacerV(16),
		widget.NewLabel("Свой шрифт (TTF/OTF), опционально"), fontPath,
		spacerV(20),
	)
	if !a.mobile {
		inner.Add(caption("ГОРЯЧИЕ КЛАВИШИ", colAccent))
		inner.Add(spacerV(4))
		inner.Add(hkRows)
		inner.Add(spacerV(6))
		inner.Add(resetHotkeysBtn)
		inner.Add(spacerV(20))
		inner.Add(caption("ДИКТОВКА (whisper.cpp, локально)", colAccent))
		inner.Add(spacerV(4))
		inner.Add(widget.NewLabel("whisper-cli:"))
		inner.Add(wbin)
		inner.Add(widget.NewLabel("Модель:"))
		inner.Add(wmodel)
		inner.Add(dlBtn)
		inner.Add(spacerV(20))
	}
	inner.Add(widget.NewButton("Экспорт прогресса (JSON)", a.exportProgress))
	inner.Add(widget.NewButton("Импорт прогресса (JSON)", a.importProgress))
	inner.Add(spacerV(24))
	inner.Add(caption("ОПАСНАЯ ЗОНА", colAccent))
	inner.Add(spacerV(4))
	if a.mobile {
		inner.Add(widget.NewButton("СБРОСИТЬ ВЕСЬ ПРОГРЕСС", a.confirmResetProgress))
	} else {
		inner.Add(hold)
		inner.Add(hold.Progress())
	}
	inner.Add(spacerV(8))
	content := container.NewScroll(inner)

	d := dialog.NewCustomConfirm("Настройки", "Сохранить", "Отмена", content, func(ok bool) {
		if !ok {
			return
		}
		a.cfg.APIKey = strings.TrimSpace(key.Text)
		a.cfg.Provider = providerIDByTitle(provSel.Selected)
		m := strings.TrimSpace(customModel.Text)
		if m == "" {
			m = modelSel.Selected
		}
		a.cfg.Model = m
		a.cfg.BaseURL = strings.TrimSpace(baseURL.Text)
		a.cfg.FontPath = strings.TrimSpace(fontPath.Text)
		a.cfg.WhisperBin = strings.TrimSpace(wbin.Text)
		a.cfg.WhisperModel = strings.TrimSpace(wmodel.Text)
		_ = saveConfig(a.cfg)
		a.ai = NewAIClient(a.cfg)
		a.th = newClaudeTheme(a.cfg.FontPath)
		a.fyneApp.Settings().SetTheme(a.th)
		if a.ai != nil {
			a.termLine("  ✓ провайдер «" + findProvider(a.cfg.Provider).Title + "», модель " + a.cfg.Model + " — готово")
		} else {
			a.termLine("  ! провайдер не настроен: укажи ключ и base URL")
		}
		a.refreshTerminal()
	}, a.win)
	d.Resize(fyne.NewSize(620, 740))
	d.Show()
}

func (a *App) resetAllProgress() {
	a.prog = newProgress()
	a.saveProgress()
	a.chatLog = nil
	a.cmdHist = nil
	a.cmdHistIdx = 0
	a.reloadFromProgress()
	a.termText = ""
	a.chatText = ""
	a.refreshTerminal()
	a.mentorSay("system", "Прогресс полностью сброшен. Начинаем с чистого листа.")
	a.resultDialog("Сброс выполнен", "Весь прогресс удалён.", true)
}

func (a *App) confirmResetProgress() {
	dialog.NewConfirm("Сброс прогресса",
		"Весь прогресс, курсы и закладки будут удалены безвозвратно. Продолжить?",
		func(ok bool) {
			if ok {
				a.resetAllProgress()
			}
		}, a.win).Show()
}

// ---------- кнопка с удержанием 5 секунд ----------

type holdButton struct {
	*widget.Button
	onDone   func()
	progress *widget.ProgressBar

	mu        sync.Mutex
	running   bool
	completed bool
	stop      chan struct{}
}

func newHoldButton(onHint, onDone func()) *holdButton {
	h := &holdButton{onDone: onDone}
	h.Button = widget.NewButton("СБРОСИТЬ ВЕСЬ ПРОГРЕСС", nil)
	h.Button.Importance = widget.DangerImportance
	h.progress = widget.NewProgressBar()
	return h
}

// Progress — индикатор заполнения при удержании; размещается рядом с кнопкой.
func (h *holdButton) Progress() *widget.ProgressBar { return h.progress }

func (h *holdButton) Tapped(*fyne.PointEvent) {
	h.mu.Lock()
	done := h.completed
	h.completed = false
	h.mu.Unlock()
	if done {
		return
	}
	dialog.ShowInformation("Сброс прогресса",
		"Удерживай кнопку 5 секунд для подтверждения.", fyne.CurrentApp().Driver().AllWindows()[0])
}

func (h *holdButton) MouseDown(e *desktop.MouseEvent) {
	if e.Button != desktop.MouseButtonPrimary {
		return
	}
	h.mu.Lock()
	h.completed = false
	if h.running {
		h.mu.Unlock()
		return
	}
	h.running = true
	ch := make(chan struct{})
	h.stop = ch
	h.mu.Unlock()
	go h.holdLoop(ch)
}

func (h *holdButton) MouseUp() {
	h.mu.Lock()
	if h.completed {
		h.mu.Unlock()
		return
	}
	if !h.running {
		h.mu.Unlock()
		return
	}
	h.running = false
	if h.stop != nil {
		close(h.stop)
		h.stop = nil
	}
	h.mu.Unlock()
	fyne.Do(func() {
		h.Button.SetText("СБРОСИТЬ ВЕСЬ ПРОГРЕСС")
		h.progress.SetValue(0)
	})
}

func (h *holdButton) holdLoop(stop chan struct{}) {
	start := time.Now()
	const total = 5 * time.Second
	tick := time.NewTicker(60 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-stop:
			return
		case <-tick.C:
			elapsed := time.Since(start)
			if elapsed >= total {
				h.mu.Lock()
				h.running = false
				h.stop = nil
				h.completed = true
				h.mu.Unlock()
				fyne.Do(func() {
					h.progress.SetValue(1)
					h.Button.SetText("УДАЛЕНО ✓")
					h.Button.Disable()
				})
				time.AfterFunc(450*time.Millisecond, func() {
					fyne.Do(func() {
						h.Button.Enable()
						h.Button.SetText("СБРОСИТЬ ВЕСЬ ПРОГРЕСС")
						h.progress.SetValue(0)
						if h.onDone != nil {
							h.onDone()
						}
					})
				})
				return
			}
			frac := float64(elapsed) / float64(total)
			secs := int((total-elapsed)/time.Second) + 1
			fyne.Do(func() {
				h.progress.SetValue(frac)
				h.Button.SetText(fmt.Sprintf("удаление… %d", secs))
			})
		}
	}
}

// ---------- сохранение и утилиты ----------

func (a *App) saveProgress() {
	if a.db == nil {
		return
	}
	data, err := json.Marshal(a.prog)
	if err != nil {
		return
	}
	_, _ = a.db.Exec(`INSERT OR REPLACE INTO progress (id, data) VALUES (1, ?)`, string(data))
}

func normalizeState(s *SandboxState) {
	if s.Workdir == "" {
		s.Workdir = "/workspace"
	}
	if s.Files == nil {
		s.Files = map[string]string{}
	}
	if s.Images == nil {
		s.Images = map[string]*ImageInfo{}
	}
	if s.Containers == nil {
		s.Containers = map[string]*ContainerInfo{}
	}
	if s.Volumes == nil {
		s.Volumes = map[string]string{}
	}
	if len(s.Networks) == 0 {
		s.Networks = []string{"bridge", "host", "none"}
	}
}

func cloneState(s SandboxState) SandboxState {
	data, _ := json.Marshal(s)
	var out SandboxState
	_ = json.Unmarshal(data, &out)
	normalizeState(&out)
	return out
}

func trimLast(s []string, n int) []string {
	if len(s) > n {
		return s[len(s)-n:]
	}
	return s
}

func trimHist(s []HistEntry, n int) []HistEntry {
	if len(s) > n {
		return s[len(s)-n:]
	}
	return s
}

func lastHist(s []HistEntry, n int) []HistEntry {
	if len(s) > n {
		return s[len(s)-n:]
	}
	return s
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// ---------- UI-хелперы ----------

func panel(inner fyne.CanvasObject, bg color.Color) fyne.CanvasObject {
	rect := canvas.NewRectangle(bg)
	rect.CornerRadius = 4
	return container.NewStack(rect, container.NewPadded(inner))
}

func spacerV(h float32) fyne.CanvasObject {
	return container.NewGridWrap(fyne.NewSize(1, h), canvas.NewRectangle(colClear))
}

func fixedHeight(h float32, inner fyne.CanvasObject) fyne.CanvasObject {
	return container.NewStack(
		container.NewGridWrap(fyne.NewSize(1, h), canvas.NewRectangle(colClear)),
		inner,
	)
}
