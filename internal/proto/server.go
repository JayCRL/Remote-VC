package proto

import (
	"context"
	"errors"
	"fmt"
	"os"
	"time"

	"remotevc-agent/internal/fs"
	"remotevc-agent/internal/project"
	"remotevc-agent/internal/session"
)

type Server struct {
	tr      Transport
	sess    *session.Session
	version string

	seqCtr int
	authed bool
}

func NewServer(tr Transport, sess *session.Session, version string) *Server {
	return &Server{tr: tr, sess: sess, version: version}
}

func (s *Server) nextSeq() int {
	s.seqCtr++
	return s.seqCtr
}

func (s *Server) send(ctx context.Context, env Envelope) error {
	b, err := Marshal(env)
	if err != nil {
		return err
	}
	return s.tr.WriteFrame(ctx, b)
}

func (s *Server) sendHelloAndUI(ctx context.Context) error {
	cwd := s.sess.Cwd()
	cap := []any{"fs", "project", "claude", "gemini"}
	if err := s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "hello", Payload: map[string]any{
		"version":      s.version,
		"capabilities": cap,
		"cwd":          cwd,
		"user":         os.Getenv("USER"),
		"host":         hostnameSafe(),
	}}); err != nil {
		return err
	}

	return s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "ui.render", Payload: defaultUI(cwd)})
}

func hostnameSafe() string {
	h, _ := os.Hostname()
	return h
}

func defaultUI(cwd string) map[string]any {
	return map[string]any{
		"panels": []any{
			map[string]any{
				"id":    "project",
				"title": "项目",
				"items": []any{
					map[string]any{"type": "input", "id": "project.query", "label": "搜索", "placeholder": "输入关键字，例如 proj"},
					map[string]any{"type": "button", "id": "fs.search", "label": "搜索目录", "paramsSchema": map[string]any{"q": "string"}},
					map[string]any{"type": "button", "id": "project.detect", "label": "识别项目", "paramsSchema": map[string]any{}},
					map[string]any{"type": "button", "id": "fs.list", "label": "列出当前目录", "paramsSchema": map[string]any{"path": "string(optional)"}},
					map[string]any{"type": "button", "id": "fs.read", "label": "读取文件", "paramsSchema": map[string]any{"path": "string"}},
					map[string]any{"type": "button", "id": "fs.write", "label": "写入文件", "paramsSchema": map[string]any{"path": "string", "content": "string"}},
				},
			},
			map[string]any{
				"id":    "claude",
				"title": "Claude",
				"items": []any{
					map[string]any{"type": "button", "id": "claude.start", "label": "启动 Claude", "paramsSchema": map[string]any{}},
					map[string]any{"type": "textarea", "id": "claude.input", "label": "需求", "placeholder": "输入你要 Claude 执行的需求"},
					map[string]any{"type": "button", "id": "claude.send", "label": "发送需求", "paramsSchema": map[string]any{"text": "string"}},
					map[string]any{"type": "button", "id": "claude.stop", "label": "停止会话", "paramsSchema": map[string]any{}},
				},
			},
			map[string]any{
				"id":    "gemini",
				"title": "Gemini",
				"items": []any{
					map[string]any{"type": "button", "id": "gemini.start", "label": "启动 Gemini", "paramsSchema": map[string]any{}},
					map[string]any{"type": "textarea", "id": "gemini.input", "label": "需求", "placeholder": "输入你要 Gemini 执行的需求"},
					map[string]any{"type": "button", "id": "gemini.send", "label": "发送需求", "paramsSchema": map[string]any{"text": "string"}},
					map[string]any{"type": "button", "id": "gemini.stop", "label": "停止会话", "paramsSchema": map[string]any{}},
				},
			},
			map[string]any{
				"id":    "terminal",
				"title": "终端",
				"items": []any{
					map[string]any{"type": "button", "id": "terminal.exec", "label": "运行命令", "paramsSchema": map[string]any{"cmd": "string", "args": "[]string(optional)", "dir": "string(optional)"}},
					map[string]any{"type": "input", "id": "terminal.input", "label": "输入", "placeholder": "发送到终端"},
					map[string]any{"type": "button", "id": "terminal.send", "label": "发送", "paramsSchema": map[string]any{"id": "string", "data": "string"}},
					map[string]any{"type": "button", "id": "terminal.kill", "label": "结束进程", "paramsSchema": map[string]any{"id": "string"}},
				},
			},
		},
		"state": map[string]any{"cwd": cwd},
	}
}

func (s *Server) Run() error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defer s.sess.Close()

	if err := s.sendHelloAndUI(ctx); err != nil {
		return err
	}

	// Forward async events (terminal.output, ui.confirm, terminal.state ...)
	s.sess.SetEmit(func(t string, payload map[string]any) {
		_ = s.send(context.Background(), Envelope{Seq: s.nextSeq(), Type: t, Payload: payload})
	})

	const timeout = 60 * time.Second
	timer := time.NewTimer(timeout)
	defer timer.Stop()

	go func() {
		for {
			select {
			case <-timer.C:
				fmt.Fprintf(os.Stderr, "Session timeout due to inactivity\n")
				cancel()
				return
			case <-ctx.Done():
				return
			}
		}
	}()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			frame, err := s.tr.ReadFrame(ctx)
			if err != nil {
				return err
			}
			timer.Reset(timeout)
			env, err := Unmarshal(frame)
			if err != nil {
				_ = s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "action.error", Payload: map[string]any{
					"seqRef": 0,
					"error":  "invalid_json",
					"detail": err.Error(),
				}})
				continue
			}

			if env.Type == "ping" {
				_ = s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "pong", Payload: map[string]any{}})
				continue
			}

			if env.Type != "ui.action" {
				continue
			}

			id, _ := env.Payload["id"].(string)
			params, _ := env.Payload["params"].(map[string]any)
			seqRef := env.Seq

			if id == "auth" {
				token, _ := params["token"].(string)
				if s.sess.Authenticate(token) {
					s.authed = true
					_ = s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "action.result", Payload: map[string]any{"seqRef": seqRef, "id": id, "ok": true}})
				} else {
					_ = s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "action.error", Payload: map[string]any{"seqRef": seqRef, "id": id, "error": "auth_failed"}})
				}
				continue
			}

			if !s.authed {
				_ = s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "action.error", Payload: map[string]any{"seqRef": seqRef, "id": id, "error": "unauthorized"}})
				continue
			}

			if id == "" {
				_ = s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "action.error", Payload: map[string]any{
					"seqRef": seqRef,
					"error":  "missing_id",
				}})
				continue
			}

			s.handleAction(ctx, seqRef, id, params)
		}
	}
}

func (s *Server) handleAction(ctx context.Context, seqRef int, id string, params map[string]any) {
	fmt.Fprintf(os.Stderr, "[DEBUG] Received Action: %s | Params: %v\n", id, params)
	
	result := func(payload map[string]any) {
		fmt.Fprintf(os.Stderr, "[DEBUG] Sending Result for: %s\n", id)
		_ = s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "action.result", Payload: merge(payload, map[string]any{"seqRef": seqRef, "id": id})})
	}
	errResult := func(code string, err error) {
		fmt.Fprintf(os.Stderr, "[DEBUG] Error in Action %s: %s\n", id, code)
		payload := map[string]any{"seqRef": seqRef, "id": id, "error": code}
		if err != nil {
			payload["detail"] = err.Error()
		}
		_ = s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "action.error", Payload: payload})
	}

	switch id {
	case "fs.list":
		path, _ := params["path"].(string)
		if path == "" {
			path, _ = params["q"].(string) // 兼容 q 参数作为路径
		}
		items, err := fs.ListDir(s.sess.Cwd(), path)
		if err != nil {
			errResult("fs_list_failed", err)
			return
		}
		result(map[string]any{"items": items, "type": "file_list"})

	case "fs.search":
		q, _ := params["q"].(string)
		if q == "" {
			q, _ = params["query"].(string) // 兼容 query 别名
		}
		if q == "" {
			errResult("missing_q", errors.New("请输入搜索关键字"))
			return
		}
		root := s.sess.AllowedRoot()
		hits, err := fs.SearchDirs(root, q, 50)
		if err != nil {
			errResult("fs_search_failed", err)
			return
		}
		result(map[string]any{"root": root, "hits": hits, "type": "search_result"})

	case "fs.read":
		path, _ := params["path"].(string)
		if path == "" {
			path, _ = params["q"].(string) // 兼容前端误传
		}
		if path == "" {
			errResult("missing_path", errors.New("未指定文件路径"))
			return
		}
		content, err := fs.ReadFile(s.sess.AllowedRoot(), path)
		if err != nil {
			errResult("fs_read_failed", err)
			return
		}
		result(map[string]any{"content": string(content), "path": path, "type": "file_content"})

	case "fs.write":
		path, _ := params["path"].(string)
		content, _ := params["content"].(string)
		if path == "" {
			errResult("missing_path", errors.New("path required"))
			return
		}
		err := fs.WriteFile(s.sess.AllowedRoot(), path, []byte(content))
		if err != nil {
			errResult("fs_write_failed", err)
			return
		}
		result(map[string]any{"ok": true})

	case "session.setCwd":
		p, _ := params["path"].(string)
		if p == "" {
			errResult("missing_path", errors.New("path required"))
			return
		}
		abs, err := fs.CleanJoin(s.sess.AllowedRoot(), p)
		if err != nil {
			errResult("invalid_path", err)
			return
		}
		if err := s.sess.SetCwd(abs); err != nil {
			errResult("setcwd_failed", err)
			return
		}
		result(map[string]any{"cwd": s.sess.Cwd()})
		_ = s.send(ctx, Envelope{Seq: s.nextSeq(), Type: "ui.render", Payload: defaultUI(s.sess.Cwd())})

	case "project.detect":
		info, err := project.Detect(s.sess.Cwd())
		if err != nil {
			errResult("project_detect_failed", err)
			return
		}
		result(map[string]any{"project": info, "type": "project_info"})

	case "claude.start":
		if err := s.sess.ClaudeStart(); err != nil {
			errResult("claude_start_failed", err)
			return
		}
		result(map[string]any{"state": "starting", "type": "ai_status"})

	case "claude.send":
		text, _ := params["text"].(string)
		if text == "" {
			errResult("missing_text", errors.New("需求内容不能为空"))
			return
		}
		if err := s.sess.ClaudeSend(text); err != nil {
			errResult("claude_send_failed", err)
			return
		}
		result(map[string]any{"sent": true, "type": "ai_action"})

	case "claude.stop":
		if err := s.sess.ClaudeStop(); err != nil {
			errResult("claude_stop_failed", err)
			return
		}
		result(map[string]any{"stopped": true, "type": "ai_action"})

	case "claude.confirm":
		approve, _ := params["approve"].(bool)
		if err := s.sess.ClaudeConfirm(approve); err != nil {
			errResult("claude_confirm_failed", err)
			return
		}
		result(map[string]any{"ok": true, "approve": approve, "type": "ai_action"})

	case "gemini.start":
		if err := s.sess.GeminiStart(); err != nil {
			errResult("gemini_start_failed", err)
			return
		}
		result(map[string]any{"state": "starting", "type": "ai_status"})

	case "gemini.send":
		text, _ := params["text"].(string)
		if text == "" {
			errResult("missing_text", errors.New("需求内容不能为空"))
			return
		}
		if err := s.sess.GeminiSend(text); err != nil {
			errResult("gemini_send_failed", err)
			return
		}
		result(map[string]any{"sent": true, "type": "ai_action"})

	case "gemini.stop":
		if err := s.sess.GeminiStop(); err != nil {
			errResult("gemini_stop_failed", err)
			return
		}
		result(map[string]any{"stopped": true, "type": "ai_action"})

	case "gemini.confirm":
		approve, _ := params["approve"].(bool)
		if err := s.sess.GeminiConfirm(approve); err != nil {
			errResult("gemini_confirm_failed", err)
			return
		}
		result(map[string]any{"ok": true, "approve": approve, "type": "ai_action"})

	case "terminal.exec":
		cmd, _ := params["cmd"].(string)
		if cmd == "" {
			errResult("missing_cmd", errors.New("cmd required"))
			return
		}
		dir, _ := params["dir"].(string)
		var args []string
		if argsInterface, ok := params["args"].([]any); ok {
			for _, a := range argsInterface {
				if s, ok := a.(string); ok {
					args = append(args, s)
				}
			}
		}
		
		termId, err := s.sess.TerminalStart(cmd, args, dir)
		if err != nil {
			errResult("terminal_start_failed", err)
			return
		}
		result(map[string]any{"id": termId})

	case "terminal.send":
		id, _ := params["id"].(string)
		data, _ := params["data"].(string)
		if id == "" {
			errResult("missing_id", errors.New("id required"))
			return
		}
		if err := s.sess.TerminalSend(id, []byte(data)); err != nil {
			errResult("terminal_send_failed", err)
			return
		}
		result(map[string]any{"sent": true})

	case "terminal.kill":
		id, _ := params["id"].(string)
		if id == "" {
			errResult("missing_id", errors.New("id required"))
			return
		}
		if err := s.sess.TerminalKill(id); err != nil {
			errResult("terminal_kill_failed", err)
			return
		}
		result(map[string]any{"killed": true})

	case "terminal.resize":
		id, _ := params["id"].(string)
		rowsF, _ := params["rows"].(float64)
		colsF, _ := params["cols"].(float64)
		if id == "" {
			errResult("missing_id", errors.New("id required"))
			return
		}
		if err := s.sess.TerminalResize(id, uint16(rowsF), uint16(colsF)); err != nil {
			errResult("terminal_resize_failed", err)
			return
		}
		result(map[string]any{"resized": true})

	default:
		errResult("unknown_action", fmt.Errorf("unknown id: %s", id))
	}
}

func merge(a map[string]any, b map[string]any) map[string]any {
	out := map[string]any{}
	for k, v := range a {
		out[k] = v
	}
	for k, v := range b {
		out[k] = v
	}
	return out
}
