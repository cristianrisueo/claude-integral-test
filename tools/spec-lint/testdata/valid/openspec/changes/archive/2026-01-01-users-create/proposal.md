# Proposal: users-create

## What we'll build

A way to delete a user, from the API and from the users table.
Test accounts stop piling up.

## What you'll see when it's done

- A `DELETE /api/users/{id}` endpoint.
- A delete button on each row of the users table.

## How we'll know it works

- `TestDeleteUser` and `TestDeleteUnknownUser` pass.
- The e2e test "deletes a user" passes.

## Decisions

- Hard delete: the row is removed. Nothing needs the history.

## Out of scope

- Soft delete and undo.
