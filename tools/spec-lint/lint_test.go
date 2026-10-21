package main

import (
	"bytes"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// Each fixture under testdata/ is an openspec/ tree. "valid" and "empty" pass;
// each L<n> tree breaks exactly one rule and must fail with that rule only.
func TestLint(t *testing.T) {
	tests := []struct {
		fixture string
		want    []string
	}{
		{"valid", nil},
		{"empty", nil},
		{"L1", []string{"L1"}},
		{"L2", []string{"L2"}},
		{"L3", []string{"L3"}},
		{"L4", []string{"L4"}},
		{"L5", []string{"L5"}},
		{"L6", []string{"L6"}},
		{"L7", []string{"L7"}},
		{"L8", []string{"L8"}},
	}
	format := regexp.MustCompile(`^openspec/\S+:\d+: L[1-8]: \S.*$`)
	for _, tt := range tests {
		t.Run(tt.fixture, func(t *testing.T) {
			violations, err := Lint(filepath.Join("testdata", tt.fixture, "openspec"))
			if err != nil {
				t.Fatalf("Lint: %v", err)
			}
			if got := rules(violations); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("rules = %v, want %v\n%s", got, tt.want, list(violations))
			}
			for _, v := range violations {
				if !format.MatchString(v.String()) {
					t.Errorf("violation %q is not \"path:line: rule: message\"", v)
				}
			}
		})
	}
}

func TestRun(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		wantCode int
		wantOut  string
	}{
		{"valid tree", []string{"testdata/valid/openspec"}, 0, "spec-lint: ok"},
		{"invalid tree", []string{"testdata/L1/openspec"}, 1, "L1: missing design.md"},
		{"no arguments", nil, 2, ""},
		{"missing directory", []string{"testdata/does-not-exist"}, 2, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			if code := run(tt.args, &stdout, &stderr); code != tt.wantCode {
				t.Errorf("exit code = %d, want %d (stderr: %s)", code, tt.wantCode, stderr.String())
			}
			if !strings.Contains(stdout.String(), tt.wantOut) {
				t.Errorf("stdout = %q, want it to contain %q", stdout.String(), tt.wantOut)
			}
		})
	}
}

func TestSplitCells(t *testing.T) {
	got := splitCells("| AC1 | Vetted | `go vet ./... | tee x` and a\\|b |")
	want := []string{"AC1", "Vetted", "`go vet ./... | tee x` and a|b"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("splitCells = %q, want %q", got, want)
	}
}

func rules(violations []Violation) []string {
	set := map[string]bool{}
	for _, v := range violations {
		set[v.Rule] = true
	}
	var out []string
	for r := range set {
		out = append(out, r)
	}
	sort.Strings(out)
	return out
}

func list(violations []Violation) string {
	var b strings.Builder
	for _, v := range violations {
		b.WriteString(v.String())
		b.WriteByte('\n')
	}
	return b.String()
}
