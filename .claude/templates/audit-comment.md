<!-- harness:audit -->
## Audit: <APPROVED | CHANGES REQUESTED>

**PR:** #<number> · **Change:** `<change-id>` · **Slice:** <NN> · **Round:** <1 | 2>

<Two or three lines: what was checked and why the verdict is what it is.>

### Findings

| #   | Severity                   | Location      | Finding   | What it breaks                                                        |
| --- | -------------------------- | ------------- | --------- | --------------------------------------------------------------------- |
| 1   | <blocking \| non-blocking> | `<path:line>` | <finding> | <acceptance criterion ID, requirement name or CLAUDE.md rule; — when non-blocking> |

### Acceptance criteria

| ID    | Asserted by                         | Verdict                                   |
| ----- | ----------------------------------- | ----------------------------------------- |
| <AC1> | <test or command that asserts it>   | <ok \| missing \| does not assert it>     |

### Terraform plan

<The plan in plain words, calling out every resource it replaces or deletes. Write "No plan for this PR." when there is none.>

### Debt issues

- <#issue title. Write "None." when there are none.>
