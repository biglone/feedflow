# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FeedFlow is an RSS feed reader application with two components:
- **Backend**: TypeScript REST API deployed on Vercel
- **iOS**: Native Swift app targeting iOS 17+

The app supports RSS feeds and YouTube channels with OAuth-based subscription import.

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
- `YOUTUBE_API_KEY` - YouTube Data API v3 key
- `GOOGLE_CLIENT_ID` - OAuth2 client ID for YouTube login
- `GOOGLE_CLIENT_SECRET` - OAuth2 client secret (may be empty for iOS)
- `GOOGLE_REDIRECT_URI` - OAuth2 redirect URI (reversed client ID format)

## iOS Development

Open `ios/FeedFlow.xcodeproj` in Xcode. The project uses Swift Package Manager with FeedKit (RSS parsing) as a dependency. Requires iOS 17+.

The app uses URL scheme `feedflow://` for OAuth callbacks (configured in Info.plist).

## Architecture

### Backend (`backend/src/`)

- **Framework**: Hono (lightweight web framework)
- **ORM**: Drizzle with PostgreSQL
- **Auth**: JWT tokens via jose library, bcrypt for password hashing

Key structure:
- `index.ts` - App entry point, middleware setup, route mounting
- `db/schema.ts` - Database schema (users, feeds, articles, folders, read/star status)
- `routes/` - API endpoints: `/api/auth`, `/api/feeds`, `/api/articles`, `/api/youtube`
- `services/rss.ts` - RSS feed fetching and parsing with rss-parser
- `lib/auth.ts` - JWT creation/verification, password hashing

The backend provides both RSS feed management and YouTube integration:
- YouTube routes handle OAuth flow and subscription import
- Articles support both RSS entries and YouTube videos

### iOS (`ios/FeedFlow/`)

- **UI**: SwiftUI
- **Persistence**: SwiftData (local) + optional backend sync via APIClient
- **Dependencies**: FeedKit (RSS parsing)

Key structure:
- `Models/` - SwiftData models: Feed, Article, Folder
- `Core/Services/FeedManager.swift` - Feed operations (add, refresh, mark read)
- `Core/Services/RSSService.swift` - Local RSS parsing with FeedKit
- `Core/Services/GoogleAuthManager.swift` - YouTube OAuth flow via ASWebAuthenticationSession
- `Core/Services/PlayerManager.swift` - Video playback for YouTube content
- `Core/Network/APIClient.swift` - Backend API communication (actor-based)
- `Features/` - UI views organized by feature (Feeds, Articles, Reader, Settings, YouTube, Player)

The app supports both local-only mode (SwiftData + RSSService) and cloud sync (APIClient).

### YouTube OAuth Flow

The iOS app uses a custom URL scheme for OAuth callbacks:

1. App requests OAuth URL from backend (`/api/youtube/oauth/url`)
2. Opens Google sign-in via `ASWebAuthenticationSession`
3. Google redirects to reversed client ID scheme: `com.googleusercontent.apps.{CLIENT_ID}:/oauth2redirect`
4. App extracts authorization code and exchanges it for tokens via backend (`/api/youtube/oauth/token`)
5. Tokens stored in iOS Keychain for persistent authentication

The reversed client ID is used as both the URL scheme and redirect URI.

### Data Model

Both platforms share the same conceptual model:
- **Users** own Feeds and Folders
- **Feeds** contain Articles and optionally belong to a Folder
- **Articles** have per-user read/starred status (backend tracks in separate `article_read_status` and `article_star_status` tables)

Article deduplication uses the `guid` field during feed refresh. YouTube videos are treated as articles with video-specific metadata.
