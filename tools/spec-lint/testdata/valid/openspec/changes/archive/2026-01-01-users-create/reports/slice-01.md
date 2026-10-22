# Slice report: users-create 01 — Delete endpoint

## What was done

You can now delete a user with `DELETE /api/users/{id}` (requirement "Delete a user").

Decisions made on Cristian's behalf:

- None.

## How we checked it

| Criterion                              | Test or command          | Result |
| -------------------------------------- | ------------------------ | ------ |
| AC1: deleting a user responds 204      | `TestDeleteUser`         | pass   |
| AC2: deleting an unknown id gives 404  | `TestDeleteUnknownUser`  | pass   |
| AC3: the package is vetted             | `go vet ./...`           | pass   |

## Check it yourself

1. `make test` — every test passes.
2. `make up` — the stack starts.
3. `curl -i -X DELETE localhost:8080/api/users/1` — the API responds 204.
