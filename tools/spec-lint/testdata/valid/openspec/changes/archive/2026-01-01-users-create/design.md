# Design: users-create

## Decisions

- **Hard delete.** The row is removed with `DELETE FROM users WHERE id = $1`.
  Reason: no requirement needs the history.

## Rejected alternatives

- **Soft delete with a `deleted_at` column.** Rejected: nothing reads deleted users.
