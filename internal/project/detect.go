package project

import (
	"bufio"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

type Info struct {
	Root string         `json:"root"`
	Kind string         `json:"kind"`
	Name string         `json:"name,omitempty"`
	Meta map[string]any `json:"meta,omitempty"`
}

func Detect(start string) (Info, error) {
	if start == "" {
		return Info{}, errors.New("start required")
	}
	cur, err := filepath.Abs(filepath.Clean(start))
	if err != nil {
		return Info{}, err
	}

	for i := 0; i < 25; i++ {
		if fi, err := os.Stat(filepath.Join(cur, "go.mod")); err == nil && !fi.IsDir() {
			name := parseGoModule(filepath.Join(cur, "go.mod"))
			return Info{Root: cur, Kind: "go", Name: name}, nil
		}
		if fi, err := os.Stat(filepath.Join(cur, "package.json")); err == nil && !fi.IsDir() {
			name := parsePackageJSONName(filepath.Join(cur, "package.json"))
			return Info{Root: cur, Kind: "node", Name: name}, nil
		}
		if fi, err := os.Stat(filepath.Join(cur, "pyproject.toml")); err == nil && !fi.IsDir() {
			return Info{Root: cur, Kind: "python"}, nil
		}
		if fi, err := os.Stat(filepath.Join(cur, "Cargo.toml")); err == nil && !fi.IsDir() {
			return Info{Root: cur, Kind: "rust"}, nil
		}
		if fi, err := os.Stat(filepath.Join(cur, ".git")); err == nil && fi.IsDir() {
			return Info{Root: cur, Kind: "git"}, nil
		}

		parent := filepath.Dir(cur)
		if parent == cur {
			break
		}
		cur = parent
	}
	return Info{Root: start, Kind: "unknown"}, nil
}

func parseGoModule(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	s := bufio.NewScanner(f)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if strings.HasPrefix(line, "module ") {
			return strings.TrimSpace(strings.TrimPrefix(line, "module "))
		}
		// keep it minimal; ignore blocks.
		if strings.HasPrefix(line, "require ") || strings.HasPrefix(line, "go ") {
			return ""
		}
	}
	return ""
}

type packageJSON struct {
	Name string `json:"name"`
}

func parsePackageJSONName(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	var pj packageJSON
	if err := json.Unmarshal(b, &pj); err != nil {
		return ""
	}
	return pj.Name
}
