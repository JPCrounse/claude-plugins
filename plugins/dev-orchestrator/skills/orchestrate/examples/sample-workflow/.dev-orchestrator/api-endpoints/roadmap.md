# Roadmap: API Endpoints

Generated: 2026-05-28T11:10:00Z
Based on: guidance.md

## Clusters

- `auth-endpoints` — Phases 1, 2 (shared context: Next.js API route conventions, Zod validation patterns, JWT helpers, rate-limit middleware)

## Phase 1: Signup & Login
Priority: High
Dependencies: Data Models complete
Cluster: auth-endpoints
Estimated items: 3

### Checklist

#### Group 1 [sequential]
1. Add Zod schemas and shared helpers (`lib/auth/schemas.ts`, `lib/auth/tokens.ts`)
   Affects: 1.2, 1.3, 2.1, 2.2

#### Group 2 [concurrent]
2. Implement `POST /api/auth/signup` route with rate-limit middleware
   Affects: none
3. Implement `POST /api/auth/login` route with rate-limit middleware and bcrypt comparison
   Affects: none

## Phase 2: Refresh & Logout
Priority: High
Dependencies: Phase 1
Cluster: auth-endpoints
Estimated items: 3

### Checklist

#### Group 1 [concurrent]
1. Implement `POST /api/auth/refresh` route with token rotation (rotated_from FK)
   Affects: none
2. Implement `POST /api/auth/logout` route that deletes the caller's Session
   Affects: none

#### Group 2 [sequential]
3. Add integration tests covering happy path and 401 cases for all four endpoints
   Affects: none
