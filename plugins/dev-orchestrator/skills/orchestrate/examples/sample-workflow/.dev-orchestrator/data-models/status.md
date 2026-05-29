# Status: Data Models

Last updated: 2026-05-28T10:30:00Z
Current phase: Phase 1

## Checklist

### Phase 1: Schema Design [PENDING]
**Group 1** [sequential]
- [ ] (todo) Define User model in `prisma/schema.prisma` with all required fields, types, and constraints
**Group 2** [concurrent]
- [ ] (todo) Define Session model with FK to User
- [ ] (todo) Define RefreshToken model with rotation support (rotated_from self-FK)
**Group 3** [sequential]
- [ ] (todo) Add indexes: User(email), Session(user_id, expires_at), RefreshToken(user_id), RefreshToken(token_hash)

### Phase 2: Migrations & Seed Data [PENDING]
**Group 1** [sequential]
- [ ] (todo) Generate Prisma migration via `prisma migrate dev --name init_auth` and review the SQL
**Group 2** [concurrent]
- [ ] (todo) Create `prisma/seed.ts` with development/test users (3 users with known credentials)
- [ ] (todo) Write migration verification test asserting all three tables and indexes exist

## Session Log

### 2026-05-28T10:30:00Z
- Roadmap generated. 2 phases, 7 items across 5 concurrency groups, 1 cluster (schema-and-migrations spanning both phases).
- Awaiting Phase 4 implementation.
