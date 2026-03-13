package fs

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

var ErrPathEscapesRoot = errors.New("path escapes root")

// CleanJoin joins root and p (if p is relative) and ensures the result stays under root.
func CleanJoin(root, p string) (string, error) {
	if root == "" {
		root = "/"
	}
	root = filepath.Clean(root)
	rootAbs, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}

	var abs string
	if p == "" {
		abs = rootAbs
	} else if filepath.IsAbs(p) {
		abs = filepath.Clean(p)
	} else {
		abs = filepath.Join(rootAbs, p)
	}
	abs, err = filepath.Abs(abs)
	if err != nil {
		return "", err
	}
	abs = filepath.Clean(abs)

	rel, err := filepath.Rel(rootAbs, abs)
	if err != nil {
		return "", err
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return "", ErrPathEscapesRoot
	}
	return abs, nil
}

type DirItem struct {
	Name    string    `json:"name"`
	Path    string    `json:"path"`
	IsDir   bool      `json:"isDir"`
	Size    int64     `json:"size"`
	Mode    string    `json:"mode"`
	ModTime time.Time `json:"modTime"`
}

func ListDir(cwd, path string) ([]DirItem, error) {
	if cwd == "" {
		cwd = "/"
	}

	var dir string
	if path == "" {
		dir = cwd
	} else if filepath.IsAbs(path) {
		dir = filepath.Clean(path)
	} else {
		dir = filepath.Join(cwd, path)
	}
	dir, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	items := make([]DirItem, 0, len(entries))
	for _, e := range entries {
		info, err := e.Info()
		if err != nil {
			continue
		}
		items = append(items, DirItem{
			Name:    e.Name(),
			Path:    filepath.Join(dir, e.Name()),
			IsDir:   e.IsDir(),
			Size:    info.Size(),
			Mode:    info.Mode().String(),
			ModTime: info.ModTime(),
		})
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].IsDir != items[j].IsDir {
			return items[i].IsDir
		}
		return strings.ToLower(items[i].Name) < strings.ToLower(items[j].Name)
	})
	return items, nil
}

// SearchDirs searches for directories whose name contains q under root.
// It is intentionally conservative to avoid walking an entire home directory.
func SearchDirs(root, q string, limit int) ([]string, error) {
	if limit <= 0 {
		limit = 50
	}
	q = strings.ToLower(strings.TrimSpace(q))
	if q == "" {
		return nil, errors.New("q required")
	}

	root = filepath.Clean(root)
	rootAbs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}

	ignore := map[string]bool{
		".git":       true,
		"node_modules": true,
		"vendor":     true,
		"dist":       true,
		"build":      true,
		".next":      true,
		"target":     true,
		".cache":     true,
		".idea":      true,
		".vscode":    true,
	}

	var hits []string
	stop := errors.New("stop")

	err = filepath.WalkDir(rootAbs, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if !d.IsDir() {
			return nil
		}

		name := d.Name()
		if path != rootAbs {
			if ignore[name] {
				return fs.SkipDir
			}
			if strings.HasPrefix(name, ".") {
				return fs.SkipDir
			}
		}

		rel, _ := filepath.Rel(rootAbs, path)
		if rel != "." {
			depth := strings.Count(rel, string(os.PathSeparator))
			if depth > 4 {
				return fs.SkipDir
			}
		}

		if strings.Contains(strings.ToLower(name), q) {
			hits = append(hits, path)
			if len(hits) >= limit {
				return stop
			}
		}
		return nil
	})
	if err != nil && !errors.Is(err, stop) {
		return hits, err
	}
	return hits, nil
}

// ReadFile reads the content of a file, ensuring the path is within the allowed root.
func ReadFile(root, path string) ([]byte, error) {
	abs, err := CleanJoin(root, path)
	if err != nil {
		return nil, err
	}
	return os.ReadFile(abs)
}

// WriteFile writes content to a file, ensuring the path is within the allowed root.
func WriteFile(root, path string, content []byte) error {
	abs, err := CleanJoin(root, path)
	if err != nil {
		return err
	}
	// Ensure the parent directory exists
	if err := os.MkdirAll(filepath.Dir(abs), 0755); err != nil {
		return err
	}
	return os.WriteFile(abs, content, 0644)
}
