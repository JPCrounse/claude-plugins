# Guidance: Data Models

Collected: 2026-05-28T10:15:00Z
Sources: 3

## Overview

Database schema and Prisma migration scaffolding for the user authentication system. Three tables — User, Session, RefreshToken — plus the indexes and validation layer the API endpoints will rely on. This topic blocks the API Endpoints topic, which depends on the User and Session models being in place.

## Specifications

- User table: id (UUID v7), email (unique, lowercased), password_hash, created_at, updated_at
- Session table: id, user_id (FK → User.id, cascade delete), token_hash, expires_at, created_at
- RefreshToken table: id, user_id (FK → User.id, cascade delete), token_hash, expires_at, rotated_from (nullable FK → self), created_at
- All foreign keys ON DELETE CASCADE
- Indexes: User(email), Session(user_id, expires_at), RefreshToken(user_id), RefreshToken(token_hash)

## Constraints

- PostgreSQL with Prisma ORM (existing project dependency — do not introduce another ORM)
- All timestamps stored in UTC
- Passwords hashed with bcrypt, minimum cost factor 12
- Maximum 5 active sessions per user (enforced at API layer, not DB constraint)

## References

- Existing schema: `prisma/schema.prisma` (currently empty — fresh slate)
- Prisma migration docs: https://www.prisma.io/docs/concepts/components/prisma-migrate
- Company security policy: passwords must meet NIST SP 800-63B guidelines

## Open Questions

- None

---
_Collection metadata: 3 sources, 0 open questions_
