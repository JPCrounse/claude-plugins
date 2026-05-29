# Roadmap: Data Models

Generated: 2026-05-28T10:30:00Z
Based on: guidance.md

## Clusters

- `schema-and-migrations` — Phases 1, 2 (shared context: Prisma schema file, migration tooling, seed scripts)

## Phase 1: Schema Design
Priority: High
Dependencies: None
Cluster: schema-and-migrations
Estimated items: 4

### Checklist

#### Group 1 [sequential]
1. Define User model in `prisma/schema.prisma` with all required fields, types, and constraints
   Affects: 1.2, 1.3, 1.4, 2.1

#### Group 2 [concurrent]
2. Define Session model with FK to User
   Affects: 1.4, 2.1
3. Define RefreshToken model with rotation support (rotated_from self-FK)
   Affects: 1.4, 2.1

#### Group 3 [sequential]
4. Add indexes: User(email), Session(user_id, expires_at), RefreshToken(user_id), RefreshToken(token_hash)
   Affects: 2.1

## Phase 2: Migrations & Seed Data
Priority: High
Dependencies: Phase 1
Cluster: schema-and-migrations
Estimated items: 3

### Checklist

#### Group 1 [sequential]
1. Generate Prisma migration via `prisma migrate dev --name init_auth` and review the SQL
   Affects: 2.2, 2.3

#### Group 2 [concurrent]
2. Create `prisma/seed.ts` with development/test users (3 users with known credentials)
   Affects: none
3. Write migration verification test asserting all three tables and indexes exist
   Affects: none
