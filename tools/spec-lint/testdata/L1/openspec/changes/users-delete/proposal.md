# Proposal: users-delete

## Why

Users cannot be removed today, so test accounts pile up.

## What changes

- A `DELETE /api/users/{id}` endpoint.
- A delete button on each row of the users table.

## Out of scope

- Soft delete and undo.
