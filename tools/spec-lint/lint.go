package main

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"
)

// Violation is one broken rule at one place in the tree.
type Violation struct {
	Path string // slash-separated, starting with the linted directory's name
	Line int    // 1-based; 0 for a finding about a whole file or folder
	Rule string // L1..L8
	Msg  string
}

func (v Violation) String() string {
	return fmt.Sprintf("%s:%d: %s: %s", v.Path, v.Line, v.Rule, v.Msg)
}

var (
	reRequirement = regexp.MustCompile(`^### Requirement:\s*(.*?)\s*$`)
	reScenario    = regexp.MustCompile(`^#### Scenario:\s*(.*?)\s*$`)
	reKeyword     = regexp.MustCompile(`\b(SHALL|MUST)\b`)
	reWhen        = regexp.MustCompile(`\bWHEN\b`)
	reThen        = regexp.MustCompile(`\bTHEN\b`)
	reReason      = regexp.MustCompile(`\*\*Reason\*\*:\s*\S`)
	reSlice       = regexp.MustCompile(`^## Slice (\d{2}) — (\S.*)$`)
	reSliceLike   = regexp.MustCompile(`^## Slice\b`)
	reTableSep    = regexp.MustCompile(`^\|?[\s:|-]*-[\s:|-]*\|?$`)
	reInlineCode  = regexp.MustCompile("`[^`]*`")
	rePlaceholder = regexp.MustCompile(`<([A-Za-z][^<>]*)>`)
	// Angle brackets that are not placeholders: autolinks and common HTML tags.
	reNotPlaceholder = regexp.MustCompile(`^((https?|mailto):|(a|b|i|p|br|hr|em|strong|code|pre|kbd|sub|sup|img|div|span|details|summary|table|tr|td|th|ul|ol|li)(\s[^>]*)?/?$)`)
)

const (
	sectionAdded    = "## ADDED Requirements"
	sectionModified = "## MODIFIED Requirements"
	sectionRemoved  = "## REMOVED Requirements"
)

// Lint checks the openspec tree rooted at root and returns every violation,
// sorted by path and line.
func Lint(root string) ([]Violation, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(abs)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("%s is not a directory", root)
	}
	l := &linter{root: abs, display: filepath.Base(abs)}
	for _, step := range []func() error{l.lintChanges, l.lintSpecs, l.lintPlaceholders} {
		if err := step(); err != nil {
			return nil, err
		}
	}
	sort.SliceStable(l.out, func(i, j int) bool {
		a, b := l.out[i], l.out[j]
		if a.Path != b.Path {
			return a.Path < b.Path
		}
		if a.Line != b.Line {
			return a.Line < b.Line
		}
		return a.Rule < b.Rule
	})
	return l.out, nil
}

type linter struct {
	root    string
	display string
	out     []Violation
}

func (l *linter) add(path string, line int, rule, format string, args ...any) {
	rel, err := filepath.Rel(l.root, path)
	if err != nil {
		rel = path
	}
	l.out = append(l.out, Violation{
		Path: filepath.ToSlash(filepath.Join(l.display, rel)),
		Line: line,
		Rule: rule,
		Msg:  fmt.Sprintf(format, args...),
	})
}

// lintChanges applies L1-L6 to every change in flight. Archived changes were
// linted before they were archived and are frozen, so only L8 reaches them.
func (l *linter) lintChanges() error {
	dir := filepath.Join(l.root, "changes")
	entries, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, e := range entries {
		if !e.IsDir() || e.Name() == "archive" || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		if err := l.lintChange(filepath.Join(dir, e.Name())); err != nil {
			return err
		}
	}
	return nil
}

func (l *linter) lintChange(dir string) error {
	for _, name := range []string{"proposal.md", "design.md", "tasks.md"} {
		if !isFile(filepath.Join(dir, name)) {
			l.add(dir, 0, "L1", "missing %s", name)
		}
	}
	specs, err := filepath.Glob(filepath.Join(dir, "specs", "*", "spec.md"))
	if err != nil {
		return err
	}
	if len(specs) == 0 {
		l.add(dir, 0, "L1", "no delta spec: expected specs/<capability>/spec.md")
	}
	for _, spec := range specs {
		if err := l.lintDelta(spec); err != nil {
			return err
		}
	}
	if tasks := filepath.Join(dir, "tasks.md"); isFile(tasks) {
		return l.lintTasks(tasks)
	}
	return nil
}

// lintDelta applies L2-L5 to a change's delta spec.
func (l *linter) lintDelta(path string) error {
	lines, err := readLines(path)
	if err != nil {
		return err
	}
	doc := parseSpec(lines)
	known := 0
	for _, s := range doc.sections {
		switch s.text {
		case sectionAdded, sectionModified, sectionRemoved:
			known++
		default:
			l.add(path, s.line, "L2", "unexpected section %q: a delta spec only has ## ADDED, ## MODIFIED and ## REMOVED Requirements", s.text)
		}
	}
	if known == 0 {
		l.add(path, 0, "L2", "no ## ADDED, ## MODIFIED or ## REMOVED Requirements section")
	}
	for _, r := range doc.requirements {
		if r.section == "" {
			l.add(path, r.line, "L2", "requirement %q is outside an ADDED, MODIFIED or REMOVED section", r.name)
		}
	}
	l.checkRequirements(path, doc.requirements)
	return nil
}

// lintSpecs applies L7 (and through it L3-L5) to openspec/specs/*/spec.md.
func (l *linter) lintSpecs() error {
	dir := filepath.Join(l.root, "specs")
	entries, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		path := filepath.Join(dir, e.Name(), "spec.md")
		if !isFile(path) {
			l.add(filepath.Join(dir, e.Name()), 0, "L7", "capability folder has no spec.md")
			continue
		}
		lines, err := readLines(path)
		if err != nil {
			return err
		}
		doc := parseSpec(lines)
		for _, want := range []string{"## Purpose", "## Requirements"} {
			if !doc.hasSection(want) {
				l.add(path, 0, "L7", "missing %q section", want)
			}
		}
		l.checkRequirements(path, doc.requirements)
	}
	return nil
}

// checkRequirements applies L3, L4 and L5. A removed requirement only needs
// its name and a **Reason**: line.
func (l *linter) checkRequirements(path string, reqs []*requirement) {
	seen := map[string]int{}
	for _, r := range reqs {
		switch first, dup := seen[r.name]; {
		case r.name == "":
			l.add(path, r.line, "L3", "requirement has no name")
		case dup:
			l.add(path, r.line, "L5", "duplicate requirement name %q (first at line %d)", r.name, first)
		default:
			seen[r.name] = r.line
		}
		if r.section == sectionRemoved {
			if !anyMatch(r.body, reReason) {
				l.add(path, r.line, "L3", "removed requirement %q needs a **Reason**: line", r.name)
			}
			continue
		}
		switch {
		case !anyNonBlank(r.body):
			l.add(path, r.line, "L3", "requirement %q has an empty body", r.name)
		case !anyMatch(r.body, reKeyword):
			l.add(path, r.line, "L3", "requirement %q has no SHALL or MUST", r.name)
		}
		if len(r.scenarios) == 0 {
			l.add(path, r.line, "L3", "requirement %q has no #### Scenario:", r.name)
		}
		for _, s := range r.scenarios {
			if !anyMatch(s.lines, reWhen) {
				l.add(path, s.line, "L4", "scenario %q has no WHEN line", s.name)
			}
			if !anyMatch(s.lines, reThen) {
				l.add(path, s.line, "L4", "scenario %q has no THEN line", s.name)
			}
		}
	}
}

// lintTasks applies L6.
func (l *linter) lintTasks(path string) error {
	lines, err := readLines(path)
	if err != nil {
		return err
	}
	type slice struct {
		num, line int
		body      []mdLine
	}
	var slices []*slice
	var cur *slice
	for _, ln := range lines {
		if !ln.code && isHeading(ln.text, 2) {
			cur = nil
			if m := reSlice.FindStringSubmatch(ln.text); m != nil {
				var num int
				fmt.Sscanf(m[1], "%d", &num)
				cur = &slice{num: num, line: ln.n}
				slices = append(slices, cur)
			} else if reSliceLike.MatchString(ln.text) {
				l.add(path, ln.n, "L6", "malformed slice heading: want \"## Slice NN — <title>\"")
			}
			continue
		}
		if cur != nil && !ln.code {
			cur.body = append(cur.body, ln)
		}
	}
	if len(slices) == 0 {
		l.add(path, 0, "L6", "no \"## Slice NN — <title>\" section")
	}
	for i, s := range slices {
		if s.num != i+1 {
			l.add(path, s.line, "L6", "slice %02d is out of sequence: want %02d (numbered from 01 without gaps)", s.num, i+1)
		}
		found := false
		for _, t := range tables(s.body) {
			col := -1
			for ci, c := range splitCells(t[0].text) {
				if strings.EqualFold(c, "Verified by") {
					col = ci
				}
			}
			if col < 0 {
				continue
			}
			found = true
			for _, row := range t[1:] {
				if reTableSep.MatchString(strings.TrimSpace(row.text)) {
					continue
				}
				cells := splitCells(row.text)
				if col >= len(cells) || cells[col] == "" {
					l.add(path, row.n, "L6", "acceptance criterion has an empty \"Verified by\" cell")
				}
			}
		}
		if !found {
			l.add(path, s.line, "L6", "slice %02d has no acceptance criteria table with a \"Verified by\" column", s.num)
		}
	}
	return nil
}

// lintPlaceholders applies L8 to every Markdown file, archive included.
// Code blocks and inline code are not checked.
func (l *linter) lintPlaceholders() error {
	return filepath.WalkDir(l.root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(d.Name(), ".md") {
			return nil
		}
		lines, err := readLines(path)
		if err != nil {
			return err
		}
		for _, ln := range lines {
			if ln.code {
				continue
			}
			text := reInlineCode.ReplaceAllString(ln.text, "")
			for _, m := range rePlaceholder.FindAllStringSubmatch(text, -1) {
				if !reNotPlaceholder.MatchString(m[1]) {
					l.add(path, ln.n, "L8", "placeholder %s left in the file", m[0])
				}
			}
		}
		return nil
	})
}

// --- Markdown parsing ---

type mdLine struct {
	n    int
	text string
	code bool // inside a fenced code block, fences included
}

func readLines(path string) ([]mdLine, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var out []mdLine
	fence := ""
	for i, text := range strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n") {
		trimmed := strings.TrimSpace(text)
		switch {
		case fence == "" && (strings.HasPrefix(trimmed, "```") || strings.HasPrefix(trimmed, "~~~")):
			fence = trimmed[:3]
			out = append(out, mdLine{i + 1, text, true})
		case fence != "":
			if strings.HasPrefix(trimmed, fence) {
				fence = ""
			}
			out = append(out, mdLine{i + 1, text, true})
		default:
			out = append(out, mdLine{i + 1, text, false})
		}
	}
	return out, nil
}

// isHeading reports whether text is an ATX heading of exactly this level.
func isHeading(text string, level int) bool {
	prefix := strings.Repeat("#", level) + " "
	return strings.HasPrefix(text, prefix)
}

type heading struct {
	text string
	line int
}

type requirement struct {
	name      string
	line      int
	section   string   // the enclosing ## heading, "" if none
	body      []string // lines between the heading and the first scenario
	scenarios []*scenario
}

type scenario struct {
	name  string
	line  int
	lines []string
}

type specDoc struct {
	sections     []heading
	requirements []*requirement
}

func (d specDoc) hasSection(text string) bool {
	return slices.ContainsFunc(d.sections, func(h heading) bool { return h.text == text })
}

func parseSpec(lines []mdLine) specDoc {
	var doc specDoc
	section := ""
	var req *requirement
	var scn *scenario
	for _, ln := range lines {
		text := strings.TrimRight(ln.text, " \t")
		if !ln.code {
			switch {
			case isHeading(text, 2):
				section = text
				doc.sections = append(doc.sections, heading{text, ln.n})
				req, scn = nil, nil
				continue
			case reRequirement.MatchString(text):
				req = &requirement{name: reRequirement.FindStringSubmatch(text)[1], line: ln.n, section: section}
				doc.requirements = append(doc.requirements, req)
				scn = nil
				continue
			case reScenario.MatchString(text):
				if req != nil {
					scn = &scenario{name: reScenario.FindStringSubmatch(text)[1], line: ln.n}
					req.scenarios = append(req.scenarios, scn)
				}
				continue
			case isHeading(text, 1) || isHeading(text, 3):
				req, scn = nil, nil
				continue
			}
		}
		switch {
		case scn != nil:
			scn.lines = append(scn.lines, text)
		case req != nil:
			req.body = append(req.body, text)
		}
	}
	return doc
}

// tables groups consecutive lines that start with "|".
func tables(lines []mdLine) [][]mdLine {
	var out [][]mdLine
	var cur []mdLine
	for _, ln := range lines {
		if strings.HasPrefix(strings.TrimSpace(ln.text), "|") {
			cur = append(cur, ln)
			continue
		}
		if len(cur) > 0 {
			out = append(out, cur)
			cur = nil
		}
	}
	if len(cur) > 0 {
		out = append(out, cur)
	}
	return out
}

// splitCells splits a table row on "|", ignoring escaped pipes and pipes
// inside inline code.
func splitCells(row string) []string {
	row = strings.TrimSpace(row)
	row = strings.TrimPrefix(row, "|")
	if strings.HasSuffix(row, "|") && !strings.HasSuffix(row, `\|`) {
		row = strings.TrimSuffix(row, "|")
	}
	var cells []string
	var b strings.Builder
	inCode := false
	for i := 0; i < len(row); i++ {
		c := row[i]
		switch {
		case c == '\\' && i+1 < len(row) && row[i+1] == '|':
			b.WriteByte('|')
			i++
		case c == '`':
			inCode = !inCode
			b.WriteByte(c)
		case c == '|' && !inCode:
			cells = append(cells, strings.TrimSpace(b.String()))
			b.Reset()
		default:
			b.WriteByte(c)
		}
	}
	return append(cells, strings.TrimSpace(b.String()))
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

func anyMatch(lines []string, re *regexp.Regexp) bool {
	return slices.ContainsFunc(lines, re.MatchString)
}

func anyNonBlank(lines []string) bool {
	return slices.ContainsFunc(lines, func(s string) bool { return strings.TrimSpace(s) != "" })
}
