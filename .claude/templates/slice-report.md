# Slice report: <change-id> <NN> — <slice goal>

## What changed and why

- <change> — implements requirement "<Requirement name>"

## How it works

<A short explanation for a reader who has not seen the code. Add a small diagram when it helps.>

## How it was tested

### Red

<The command run against the stubs and the failing assertions it printed (trimmed).>

### Green

| Command      | Result                                                        |
| ------------ | ------------------------------------------------------------- |
| `make check` | <pass, or the failure>                                        |
| `make test`  | <pass, with test counts>                                      |
| `make e2e`   | <pass with counts, or "not run: the slice touches neither UI nor API"> |

### Acceptance criteria

| ID    | Verified by                  | Result |
| ----- | ---------------------------- | ------ |
| <AC1> | <test or command>            | <pass> |

## Decisions made on Cristian's behalf

- <decision and its reason. Write "None." when there are none.>

## Risks and debt

- <risk or debt. Write "None." when there are none.>

## Check it yourself

1. `<command>` — <what you should see>
2. `<command>` — <what you should see>
3. `<command>` — <what you should see>
