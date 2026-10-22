# Users specification

## Purpose

Manage the people who use the system: create, read, update and delete users
through the web UI and the `/api/users` endpoints.

## Requirements

### Requirement: Create a user

The system SHALL create a user with a name and a unique email.

#### Scenario: Valid user

- **WHEN** a user is created with a name and an unused email
- **THEN** the API responds 201 with the new user

#### Scenario: Duplicate email

- **WHEN** a user is created with an email that already exists
- **THEN** the API responds 409 with code `email_taken`
- **AND** no user is created

### Requirement: List users

The system MUST return users ordered by creation date, newest first.

#### Scenario: Two users

- **WHEN** two users exist
- **THEN** the list returns the newest one first
