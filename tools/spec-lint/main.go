// Command spec-lint checks an openspec/ tree against the repository's spec
// format (docs/harness-spec.md, sections 3.6 and 3.7).
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
