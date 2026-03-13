package session

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"remotevc-agent/internal/ai"
	"remotevc-agent/internal/config"
	"remotevc-agent/internal/notify"
	"remotevc-agent/internal/terminal"
)

type EmitFn func(t string, payload map[string]any)

type Session struct {
	mu sync.Mutex

	cwd         string
	allowedRoot string
	emit        EmitFn

	token string

	claude *ai.Session
	gemini *ai.Session
	state  string

	terminals map[string]*terminal.Session

	rules config.ConfirmRules
}

func New(token string) *Session {
	home, _ := os.UserHomeDir()
	if home == "" {
		home = "/"
	}
	cwd, _ := os.Getwd()
	if cwd == "" {
		cwd = home
	}

	rules, _ := config.LoadConfirmRules()

	s := &Session{
		cwd:         cwd,
		allowedRoot: home,
		rules:       rules,
		state:       "idle",
		token:       token,
		terminals:   make(map[string]*terminal.Session),
	}
	return s
}

func (s *Session) Authenticate(token string) bool {
	return s.token == "" || s.token == token
}

func (s *Session) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.claude != nil {
		_ = s.claude.Stop()
		s.claude = nil
	}
	if s.gemini != nil {
		_ = s.gemini.Stop()
		s.gemini = nil
	}
	for id, ts := range s.terminals {
		_ = ts.Stop()
		delete(s.terminals, id)
	}
	s.state = "idle"
}

func (s *Session) SetEmit(fn EmitFn) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.emit = fn
}

func (s *Session) emitEvent(t string, payload map[string]any) {
	s.mu.Lock()
	emit := s.emit
	s.mu.Unlock()
	if emit != nil {
		emit(t, payload)
	}
}

func (s *Session) Cwd() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.cwd
}

func (s *Session) AllowedRoot() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.allowedRoot
}

func (s *Session) SetCwd(abs string) error {
	abs = filepath.Clean(abs)
	st, err := os.Stat(abs)
	if err != nil {
		return err
	}
	if !st.IsDir() {
		return errors.New("not a directory")
	}

	s.mu.Lock()
	s.cwd = abs
	s.mu.Unlock()

	s.emitEvent("terminal.state", map[string]any{"state": "cwd_changed", "cwd": abs})
	return nil
}

func (s *Session) aiStart(aiType string, cmdName string, args []string) error {
	s.mu.Lock()
	var current **ai.Session
	if aiType == "claude" {
		current = &s.claude
	} else {
		current = &s.gemini
	}

	if *current != nil {
		s.mu.Unlock()
		return errors.New(aiType + " session already running")
	}
	cwd := s.cwd
	rules := s.rules
	s.state = "starting"
	s.mu.Unlock()

	s.emitEvent("terminal.state", map[string]any{"state": "starting", "ai": aiType})

	as, err := ai.Start(ai.StartOptions{
		CmdName: cmdName,
		Args:    args,
		Dir:     cwd,
		OnOutput: func(raw []byte, text string) {
			s.emitEvent("terminal.output", map[string]any{"raw": string(raw), "text": text, "ai": aiType})
		},
		OnState: func(state string) {
			s.emitEvent("terminal.state", map[string]any{"state": state, "ai": aiType})
		},
		OnConfirm: func(prompt string, contextLines []string) {
			s.mu.Lock()
			s.state = "waiting_confirm"
			s.mu.Unlock()
			s.emitEvent("ui.confirm", map[string]any{"prompt": prompt, "context": contextLines, "ai": aiType})
			notify.Send("Permission Required", fmt.Sprintf("%s needs your approval: %s", aiType, prompt))
		},
		Rules: rules,
	})
	if err != nil {
		s.mu.Lock()
		s.state = "idle"
		s.mu.Unlock()
		return err
	}

	s.mu.Lock()
	*current = as
	s.state = "running"
	s.mu.Unlock()

	return nil
}

func (s *Session) ClaudeStart() error {
	return s.aiStart("claude", "claude", nil)
}

func (s *Session) ClaudeSend(text string) error {
	s.mu.Lock()
	cs := s.claude
	s.mu.Unlock()
	if cs == nil {
		return errors.New("claude not started")
	}
	return cs.Send(text)
}

func (s *Session) ClaudeStop() error {
	s.mu.Lock()
	cs := s.claude
	s.mu.Unlock()
	if cs == nil {
		return nil
	}
	err := cs.Stop()
	s.mu.Lock()
	s.claude = nil
	s.state = "idle"
	s.mu.Unlock()
	return err
}

func (s *Session) ClaudeConfirm(approve bool) error {
	s.mu.Lock()
	cs := s.claude
	s.mu.Unlock()
	if cs == nil {
		return errors.New("claude not started")
	}
	var resp string
	if approve {
		resp = "y\n"
	} else {
		resp = "n\n"
	}
	if err := cs.WriteRaw([]byte(resp)); err != nil {
		return err
	}
	s.mu.Lock()
	s.state = "running"
	s.mu.Unlock()
	s.emitEvent("terminal.state", map[string]any{"state": "running", "ai": "claude"})
	return nil
}

func (s *Session) GeminiStart() error {
	return s.aiStart("gemini", "gemini", nil)
}

func (s *Session) GeminiSend(text string) error {
	s.mu.Lock()
	gs := s.gemini
	s.mu.Unlock()
	if gs == nil {
		return errors.New("gemini not started")
	}
	return gs.Send(text)
}

func (s *Session) GeminiStop() error {
	s.mu.Lock()
	gs := s.gemini
	s.mu.Unlock()
	if gs == nil {
		return nil
	}
	err := gs.Stop()
	s.mu.Lock()
	s.gemini = nil
	s.state = "idle"
	s.mu.Unlock()
	return err
}

func (s *Session) GeminiConfirm(approve bool) error {
	s.mu.Lock()
	gs := s.gemini
	s.mu.Unlock()
	if gs == nil {
		return errors.New("gemini not started")
	}
	var resp string
	if approve {
		resp = "y\n"
	} else {
		resp = "n\n"
	}
	if err := gs.WriteRaw([]byte(resp)); err != nil {
		return err
	}
	s.mu.Lock()
	s.state = "running"
	s.mu.Unlock()
	s.emitEvent("terminal.state", map[string]any{"state": "running", "ai": "gemini"})
	return nil
}

func genTermId() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (s *Session) TerminalStart(cmdName string, args []string, dir string) (string, error) {
	if dir == "" {
		s.mu.Lock()
		dir = s.cwd
		s.mu.Unlock()
	}

	termId := genTermId()
	ts, err := terminal.Start(cmdName, args, dir)
	if err != nil {
		return "", err
	}

	ts.OnOutput = func(raw []byte) {
		s.emitEvent("terminal.pty.output", map[string]any{"id": termId, "raw": string(raw)})
	}
	ts.OnState = func(state string) {
		s.emitEvent("terminal.pty.state", map[string]any{"id": termId, "state": state})
		if state == "stopped" {
			s.mu.Lock()
			delete(s.terminals, termId)
			s.mu.Unlock()
		}
	}

	s.mu.Lock()
	s.terminals[termId] = ts
	s.mu.Unlock()

	return termId, nil
}

func (s *Session) TerminalSend(termId string, data []byte) error {
	s.mu.Lock()
	ts, ok := s.terminals[termId]
	s.mu.Unlock()
	if !ok {
		return errors.New("terminal not found")
	}
	return ts.WriteRaw(data)
}

func (s *Session) TerminalKill(termId string) error {
	s.mu.Lock()
	ts, ok := s.terminals[termId]
	s.mu.Unlock()
	if !ok {
		return errors.New("terminal not found")
	}
	return ts.Stop()
}

func (s *Session) TerminalResize(termId string, rows, cols uint16) error {
	s.mu.Lock()
	ts, ok := s.terminals[termId]
	s.mu.Unlock()
	if !ok {
		return errors.New("terminal not found")
	}
	return ts.Resize(rows, cols)
}
