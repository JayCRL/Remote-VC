package ai

import (
	"bufio"
	"errors"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"remotevc-agent/internal/config"
)

type StartOptions struct {
	CmdName   string
	Args      []string
	Dir       string
	OnOutput  func(raw []byte, text string)
	OnState   func(state string)
	OnConfirm func(prompt string, contextLines []string)
	Rules     config.ConfirmRules
}

type Session struct {
	mu sync.Mutex

	cmd   *exec.Cmd
	stdin io.WriteCloser

	closed chan struct{}
	waitErr atomic.Value // error

	waitingConfirm atomic.Bool
	linesMu        sync.Mutex
	lastLines      []string
	maxLines       int

	onOutput  func(raw []byte, text string)
	onState   func(state string)
	onConfirm func(prompt string, contextLines []string)

	rules config.ConfirmRules
}

func Start(opts StartOptions) (*Session, error) {
	cmdName := opts.CmdName
	if cmdName == "" {
		cmdName = "claude"
	}

	cmd := exec.Command(cmdName, opts.Args...)
	if opts.Dir != "" {
		cmd.Dir = opts.Dir
	}
	cmd.Env = os.Environ()

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, err
	}

	s := &Session{
		cmd:       cmd,
		stdin:     stdin,
		closed:    make(chan struct{}),
		maxLines:  30,
		onOutput:  opts.OnOutput,
		onState:   opts.OnState,
		onConfirm: opts.OnConfirm,
		rules:     opts.Rules,
	}
	if s.rules.Default == "" {
		s.rules = config.DefaultConfirmRules()
	}

	if s.onState != nil {
		s.onState("starting")
	}

	if err := cmd.Start(); err != nil {
		return nil, err
	}

	go s.readStream(stdout)
	go s.readStream(stderr)
	go s.wait()

	if s.onState != nil {
		s.onState("running")
	}

	return s, nil
}

func (s *Session) wait() {
	err := s.cmd.Wait()
	s.waitErr.Store(err)
	if err != nil {
		if s.onOutput != nil {
			s.onOutput([]byte("\n[AI 进程异常退出: "+err.Error()+"]\n"), "\n[AI 进程异常退出: "+err.Error()+"]\n")
		}
	}
	close(s.closed)
	if s.onState != nil {
		s.onState("stopped")
	}
}

func (s *Session) readStream(r io.Reader) {
	br := bufio.NewReaderSize(r, 1<<16)
	for {
		line, err := br.ReadBytes('\n')
		if len(line) > 0 {
			text := string(line)
			s.appendLine(strings.TrimRight(text, "\r\n"))
			if s.onOutput != nil {
				s.onOutput(line, text)
			}
			s.maybeHandleConfirm(strings.TrimRight(text, "\r\n"))
		}
		if err != nil {
			if !errors.Is(err, io.EOF) {
				// still report via output channel
				if s.onOutput != nil {
					s.onOutput([]byte(err.Error()+"\n"), err.Error()+"\n")
				}
			}
			return
		}
	}
}

func (s *Session) appendLine(line string) {
	if line == "" {
		return
	}
	s.linesMu.Lock()
	defer s.linesMu.Unlock()
	s.lastLines = append(s.lastLines, line)
	if len(s.lastLines) > s.maxLines {
		s.lastLines = s.lastLines[len(s.lastLines)-s.maxLines:]
	}
}

var confirmRe = regexp.MustCompile(`(?i)(\(y/n\)|\[y/n\]|\(yes/no\)|\byes\b.*\bno\b|\by\s*/\s*n\b|\bconfirm\b|\bapprove\b|\bproceed\?|继续吗？|是否确认)`)

func (s *Session) maybeHandleConfirm(prompt string) {
	if prompt == "" {
		return
	}
	if !confirmRe.MatchString(prompt) {
		return
	}

	// Don't fire multiple confirm events for the same pause.
	if s.waitingConfirm.Load() {
		return
	}

	decided, approve, _ := s.rules.Decide(prompt)
	if decided {
		_ = s.WriteRaw([]byte(map[bool]string{true: "y\n", false: "n\n"}[approve]))
		if s.onState != nil {
			s.onState("auto_confirm")
		}
		return
	}

	if !s.waitingConfirm.CompareAndSwap(false, true) {
		return
	}

	var ctx []string
	s.linesMu.Lock()
	ctx = append(ctx, s.lastLines...)
	s.linesMu.Unlock()

	if s.onConfirm != nil {
		s.onConfirm(prompt, ctx)
	}
}

func (s *Session) Send(text string) error {
	if text == "" {
		return nil
	}
	return s.WriteRaw([]byte(text + "\n"))
}

func (s *Session) WriteRaw(b []byte) error {
	s.mu.Lock()
	stdin := s.stdin
	s.mu.Unlock()
	if stdin == nil {
		return errors.New("stdin closed")
	}
	_, err := stdin.Write(b)
	if err == nil {
		// If we were waiting for confirmation, any input likely unblocks it.
		if s.waitingConfirm.Load() {
			s.waitingConfirm.Store(false)
			if s.onState != nil {
				s.onState("confirmed")
			}
		}
	}
	return err
}

func (s *Session) Stop() error {
	s.mu.Lock()
	cmd := s.cmd
	s.mu.Unlock()
	if cmd == nil || cmd.Process == nil {
		return nil
	}

	_ = cmd.Process.Signal(os.Interrupt)
	select {
	case <-s.closed:
		if v := s.waitErr.Load(); v != nil {
			if err, ok := v.(error); ok {
				return err
			}
		}
		return nil
	case <-time.After(2 * time.Second):
		_ = cmd.Process.Kill()
		<-s.closed
		if v := s.waitErr.Load(); v != nil {
			if err, ok := v.(error); ok {
				return err
			}
		}
		return nil
	}
}
