// Command spec-lint checks an openspec/ tree against the repository's spec
// format:
//
//	L1  a change in flight has proposal.md, tasks.md and at least one specs/<capability>/spec.md.
//	L2  a delta spec has only ## ADDED, ## MODIFIED and ## REMOVED Requirements, and every requirement sits in one.
//	L3  a requirement has a name, a SHALL or MUST and a #### Scenario:; a removed one has a **Reason**: line.
//	L4  a scenario has a WHEN line and a THEN line.
//	L5  requirement names are unique within a spec file.
//	L6  tasks.md has "## Slice NN — <title>" sections numbered from 01 without gaps, each with an
//	    acceptance criteria table whose "Verified by" cells are all filled.
//	L7  each openspec/specs/<capability>/ has a spec.md with ## Purpose and ## Requirements.
//	L8  no <placeholder> is left in any Markdown file, archive included.
//
// Usage: spec-lint <openspec-dir>
//
// It prints every violation as "path:line: rule: message" and exits 1 when
// there is at least one, 2 on a usage or I/O error, and 0 otherwise.
package main

import (
	"fmt"
	"io"
	"os"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) != 1 {
		fmt.Fprintln(stderr, "usage: spec-lint <openspec-dir>")
		return 2
	}
	violations, err := Lint(args[0])
	if err != nil {
		fmt.Fprintf(stderr, "spec-lint: %v\n", err)
		return 2
	}
	for _, v := range violations {
		fmt.Fprintln(stdout, v)
	}
	if len(violations) > 0 {
		fmt.Fprintf(stderr, "spec-lint: %d violation(s)\n", len(violations))
		return 1
	}
	fmt.Fprintln(stdout, "spec-lint: ok")
	return 0
}
