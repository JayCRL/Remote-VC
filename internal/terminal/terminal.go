package terminal

import (
	"errors"
	"io"
	"os"
	"os/exec"
	"sync"
	"sync/atomic"

	"github.com/creack/pty"
)

type Session struct {
	mu sync.Mutex

	cmd  *exec.Cmd
	ptmx *os.File

	closed  chan struct{}
	waitErr atomic.Value // error

	OnOutput func(raw []byte)
	OnState  func(state string)
}

func Start(cmdName string, args []string, dir string) (*Session, error) {
	cmd := exec.Command(cmdName, args...)
	if dir != "" {
		cmd.Dir = dir
	}
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")

	ptmx, err := pty.Start(cmd)
	if err != nil {
		return nil, err
	}

	s := &Session{
		cmd:    cmd,
		ptmx:   ptmx,
		closed: make(chan struct{}),
	}

	go s.readStream()
	go s.wait()

	return s, nil
}

func (s *Session) wait() {
	err := s.cmd.Wait()
	s.waitErr.Store(err)
	close(s.closed)
	if s.OnState != nil {
		s.OnState("stopped")
	}
}

func (s *Session) readStream() {
	buf := make([]byte, 1024)
	for {
		n, err := s.ptmx.Read(buf)
		if n > 0 && s.OnOutput != nil {
			s.OnOutput(buf[:n])
		}
		if err != nil {
			if !errors.Is(err, io.EOF) && !errors.Is(err, os.ErrClosed) {
				if s.OnOutput != nil {
					s.OnOutput([]byte("\n[error reading pty: " + err.Error() + "]\n"))
				}
			}
			return
		}
	}
}

func (s *Session) WriteRaw(b []byte) error {
	s.mu.Lock()
	ptmx := s.ptmx
	s.mu.Unlock()
	if ptmx == nil {
		return errors.New("terminal closed")
	}
	_, err := ptmx.Write(b)
	return err
}

func (s *Session) Stop() error {
	s.mu.Lock()
	cmd := s.cmd
	ptmx := s.ptmx
	s.mu.Unlock()
	if cmd == nil || cmd.Process == nil {
		return nil
	}
	
	_ = ptmx.Close()
	_ = cmd.Process.Kill()
	<-s.closed
	return nil
}

func (s *Session) Resize(rows, cols uint16) error {
	s.mu.Lock()
	ptmx := s.ptmx
	s.mu.Unlock()
	if ptmx == nil {
		return errors.New("terminal closed")
	}
	return pty.Setsize(ptmx, &pty.Winsize{Rows: rows, Cols: cols})
}