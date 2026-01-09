# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FeedFlow is an RSS feed reader application with two components:
- **Backend**: TypeScript REST API deployed on Vercel
- **iOS**: Native Swift app targeting iOS 17+

## Backend Commands

All commands run from the `backend/` directory:

```bash
npm run dev          # Start dev server with hot reload (tsx watch)
npm run build        # Compile TypeScript
npm start            # Run compiled app

# Database (Drizzle + Neon PostgreSQL)
npm run db:generate  # Generate migrations from schema changes
npm run db:migrate   # Apply migrations
npm run db:studio    # Open Drizzle Studio GUI
```

Required environment variables (see `.env.example`):
- `DATABASE_URL` - Neon PostgreSQL connection string
- `JWT_SECRET` - Secret for JWT signing
- `PORT` - Server port (default: 3000)

## iOS Development

Open `ios/FeedFlow/` in Xcode. The project uses Swift Package Manager with FeedKit as a dependency. Requires iOS 17+.

## Architecture

### Backend (`backend/src/`)

- **Framework**: Hono (lightweight web framework)
- **ORM**: Drizzle with PostgreSQL
- **Auth**: JWT tokens via jose library, bcrypt for password hashing

Key structure:
- `index.ts` - App entry point, middleware setup, route mounting
- `db/schema.ts` - Database schema (users, feeds, articles, folders, read/star status)
- `routes/` - API endpoints (auth, feeds, articles)
- `services/rss.ts` - RSS feed fetching and parsing with rss-parser
- `lib/auth.ts` - JWT creation/verification, password hashing

API routes are mounted at `/api/auth`, `/api/feeds`, `/api/articles`.

### iOS (`ios/FeedFlow/`)

- **UI**: SwiftUI
- **Persistence**: SwiftData (local) + optional backend sync via APIClient

Key structure:
- `Models/` - SwiftData models: Feed, Article, Folder
- `Core/Services/FeedManager.swift` - Feed operations (add, refresh, mark read)
- `Core/Services/RSSService.swift` - Local RSS parsing with FeedKit
- `Core/Network/APIClient.swift` - Backend API communication (actor-based)
- `Features/` - UI views organized by feature (Feeds, Articles, Reader, Settings)

The app supports both local-only mode (SwiftData + RSSService) and cloud sync (APIClient).

### Data Model

Both platforms share the same conceptual model:
- **Users** own Feeds and Folders
- **Feeds** contain Articles and optionally belong to a Folder
- **Articles** have per-user read/starred status (backend tracks in separate tables)

Article deduplication uses the `guid` field during feed refresh.
