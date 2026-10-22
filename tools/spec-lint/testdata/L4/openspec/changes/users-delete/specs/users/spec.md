# Users — delta for users-delete

## ADDED Requirements

### Requirement: Delete a user

The system SHALL delete a user by id.

#### Scenario: Existing user

- **WHEN** an existing user is deleted
- **THEN** the API responds 204
- **AND** the user no longer appears in the list

#### Scenario: Unknown user

- **WHEN** a user id that does not exist is deleted

## MODIFIED Requirements

### Requirement: List users

The system MUST return users ordered by creation date, newest first, and
SHALL NOT return deleted users.

#### Scenario: Deleted user

- **WHEN** a user has been deleted
- **THEN** the list does not include them

## REMOVED Requirements

### Requirement: Deactivate a user

**Reason**: Deleting replaces deactivating.
