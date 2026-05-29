# Guidance: API Endpoints

Collected: 2026-05-28T10:55:00Z
Sources: 2

## Overview

REST endpoints for the authentication flows. Depends on the Data Models topic completing first (User, Session, RefreshToken tables must exist). All endpoints live under `/api/auth/`.

## Specifications

- `POST /api/auth/signup` — body `{ email, password }`, returns 201 with `{ user, accessToken, refreshToken }`
- `POST /api/auth/login` — body `{ email, password }`, returns 200 with `{ user, accessToken, refreshToken }` or 401
- `POST /api/auth/refresh` — body `{ refreshToken }`, returns 200 with `{ accessToken, refreshToken }` (rotates the refresh token)
- `POST /api/auth/logout` — header `Authorization: Bearer <accessToken>`, returns 204; deletes the associated Session
- Access tokens are short-lived JWTs (15 min); refresh tokens are opaque random strings (30 days) hashed in DB

## Constraints

- Framework: Next.js App Router API routes
- Validation: Zod schemas per endpoint
- Password comparison: bcrypt.compare (timing-safe)
- Rate limiting: per-IP 10 requests/min on signup and login (existing middleware at `lib/rate-limit.ts`)

## References

- Existing rate-limit middleware: `lib/rate-limit.ts`
- JWT library: `jsonwebtoken` (already installed)

## Open Questions

- None

---
_Collection metadata: 2 sources, 0 open questions_
