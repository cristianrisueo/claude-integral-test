# Tasks: <change-id>

## Slice 01 — <slice goal>

**Goal:** <one sentence: what is true after this slice that was not true before>

**Requirements:** <requirement names from the delta specs that this slice implements>

**Scope:** <the endpoint, schema change or deployment step, with its tests>

**Out of scope:** <what waits for a later slice>

### Acceptance criteria

| ID  | Criterion                                                    | Verified by                                    |
| --- | ------------------------------------------------------------ | ---------------------------------------------- |
| AC1 | <observable behaviour, e.g. POST /api/users with a new email responds 201> | <test name and file, e.g. TestCreateUser in api/users_test.go> |
| AC2 | <observable behaviour, e.g. a duplicate email responds 409 email_taken> | <test name and file, or the exact command> |
