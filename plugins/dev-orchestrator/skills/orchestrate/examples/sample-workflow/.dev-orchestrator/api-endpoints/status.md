# Status: API Endpoints

Last updated: 2026-05-28T11:10:00Z
Current phase: Phase 1

## Checklist

### Phase 1: Signup & Login [PENDING]
**Group 1** [sequential]
- [ ] (todo) Add Zod schemas and shared helpers (`lib/auth/schemas.ts`, `lib/auth/tokens.ts`)
**Group 2** [concurrent]
- [ ] (todo) Implement `POST /api/auth/signup` route with rate-limit middleware
- [ ] (todo) Implement `POST /api/auth/login` route with rate-limit middleware and bcrypt comparison

### Phase 2: Refresh & Logout [PENDING]
**Group 1** [concurrent]
- [ ] (todo) Implement `POST /api/auth/refresh` route with token rotation (rotated_from FK)
- [ ] (todo) Implement `POST /api/auth/logout` route that deletes the caller's Session
**Group 2** [sequential]
- [ ] (todo) Add integration tests covering happy path and 401 cases for all four endpoints

## Session Log

### 2026-05-28T11:10:00Z
- Roadmap generated. 2 phases, 6 items across 4 concurrency groups, 1 cluster (auth-endpoints spanning both phases).
- Awaiting Phase 4 implementation. Depends on Data Models topic completion.
