package config

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type ConfirmRule struct {
	// Match is a case-insensitive substring match against the prompt.
	Match string `json:"match"`
	// Regex is an optional regex match against the prompt (RE2 syntax).
	Regex string `json:"regex,omitempty"`
	// Approve indicates whether to auto-approve (true) or auto-deny (false).
	Approve bool `json:"approve"`
	// Name is optional, only for debugging/UI.
	Name string `json:"name,omitempty"`
}

type ConfirmRules struct {
	Rules   []ConfirmRule `json:"rules"`
	Default string        `json:"default"` // "ask" | "approve" | "deny"
}

func DefaultConfirmRules() ConfirmRules {
	return ConfirmRules{Default: "ask"}
}

func LoadConfirmRules() (ConfirmRules, error) {
	path := os.Getenv("REMOTEVC_CONFIRM_RULES")
	if path == "" {
		home, _ := os.UserHomeDir()
		if home == "" {
			return DefaultConfirmRules(), nil
		}
		path = filepath.Join(home, ".config", "remotevc-agent", "confirm_rules.json")
	}

	b, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return DefaultConfirmRules(), nil
		}
		return DefaultConfirmRules(), err
	}

	var r ConfirmRules
	if err := json.Unmarshal(b, &r); err != nil {
		return DefaultConfirmRules(), err
	}
	if r.Default == "" {
		r.Default = "ask"
	}
	return r, nil
}

func (r ConfirmRules) Decide(prompt string) (decided bool, approve bool, ruleName string) {
	p := strings.ToLower(prompt)
	for _, rule := range r.Rules {
		if rule.Match != "" {
			if strings.Contains(p, strings.ToLower(rule.Match)) {
				return true, rule.Approve, rule.Name
			}
		}
		if rule.Regex != "" {
			re, err := regexp.Compile(rule.Regex)
			if err != nil {
				continue
			}
			if re.MatchString(prompt) {
				return true, rule.Approve, rule.Name
			}
		}
	}

	switch strings.ToLower(r.Default) {
	case "approve", "allow", "yes", "y":
		return true, true, "default"
	case "deny", "no", "n":
		return true, false, "default"
	default:
		return false, false, ""
	}
}
