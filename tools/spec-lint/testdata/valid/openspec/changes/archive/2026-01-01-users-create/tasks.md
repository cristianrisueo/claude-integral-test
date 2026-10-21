# Tasks: users-create

## Slice 01 — Delete endpoint

**Goal:** `DELETE /api/users/{id}` removes a user.

**Scope:** the handler, its route and its tests.

**Out of scope:** the UI.

### Acceptance criteria

| ID   | Criterion                                   | Verified by                              |
| ---- | ------------------------------------------- | ---------------------------------------- |
| AC1  | Deleting an existing user responds 204      | `TestDeleteUser` in `api/users_test.go`  |
| AC2  | Deleting an unknown id responds 404         | `TestDeleteUnknownUser`                  |
| AC3  | The package is vetted                       | `go vet ./... \| tee vet.log`            |

## Slice 02 — Delete button

**Goal:** each row of the users table has a delete button.

**Scope:** the button and its e2e test.

**Out of scope:** confirmation dialogs.

### Acceptance criteria

| ID  | Criterion                         | Verified by                                    |
| --- | --------------------------------- | ---------------------------------------------- |
| AC1 | Clicking delete removes the row   | `e2e/users.spec.ts` "deletes a user"           |
| AC2 | The suite passes                  | `make e2e | tail -n 5`                         |
