package proto

import (
	"bufio"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"sync"
	"time"
)

type Transport interface {
	ReadFrame(ctx context.Context) ([]byte, error)
	WriteFrame(ctx context.Context, b []byte) error
	Close() error
}

type stdioTransport struct {
	r *bufio.Reader
	w *bufio.Writer
	wc io.Closer

	mu sync.Mutex
}

func NewStdioTransport(r io.Reader, w io.Writer) Transport {
	wc, _ := w.(io.Closer)
	return NewStdioTransportWithCloser(r, w, wc)
}

func NewStdioTransportWithCloser(r io.Reader, w io.Writer, wc io.Closer) Transport {
	return &stdioTransport{
		r:  bufio.NewReaderSize(r, 1<<16),
		w:  bufio.NewWriterSize(w, 1<<16),
		wc: wc,
	}
}

func (t *stdioTransport) ReadFrame(ctx context.Context) ([]byte, error) {
	// stdin is not cancellable without extra goroutine; keep it simple for MVP.
	var lenBuf [4]byte
	if _, err := io.ReadFull(t.r, lenBuf[:]); err != nil {
		return nil, err
	}
	n := binary.BigEndian.Uint32(lenBuf[:])
	if n == 0 {
		return nil, errors.New("empty frame")
	}
	if n > 32*1024*1024 {
		return nil, fmt.Errorf("frame too large: %d", n)
	}
	b := make([]byte, n)
	if _, err := io.ReadFull(t.r, b); err != nil {
		return nil, err
	}
	return b, nil
}

func (t *stdioTransport) WriteFrame(ctx context.Context, b []byte) error {
	// Best-effort ctx: if deadline exceeded before write starts, abort.
	if deadline, ok := ctx.Deadline(); ok {
		if time.Now().After(deadline) {
			return context.DeadlineExceeded
		}
	}

	if len(b) == 0 {
		return errors.New("empty payload")
	}
	if len(b) > 32*1024*1024 {
		return fmt.Errorf("payload too large: %d", len(b))
	}

	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(b)))

	t.mu.Lock()
	defer t.mu.Unlock()

	if _, err := t.w.Write(lenBuf[:]); err != nil {
		return err
	}
	if _, err := t.w.Write(b); err != nil {
		return err
	}
	return t.w.Flush()
}

func (t *stdioTransport) Close() error {
	t.mu.Lock()
	defer t.mu.Unlock()
	_ = t.w.Flush()
	if t.wc != nil {
		return t.wc.Close()
	}
	return nil
}

type Envelope struct {
	Seq     int            `json:"seq"`
	Type    string         `json:"type"`
	Payload map[string]any `json:"payload,omitempty"`
}

func Marshal(env Envelope) ([]byte, error) {
	return json.Marshal(env)
}

func Unmarshal(b []byte) (Envelope, error) {
	var env Envelope
	err := json.Unmarshal(b, &env)
	return env, err
}
