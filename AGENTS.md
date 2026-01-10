# Repository Guidelines

## Project Structure & Module Organization

- `backend/`: TypeScript REST API (Hono) deployed to Vercel.
  - `backend/src/index.ts`: app entry point, middleware, route mounting.
  - `backend/src/routes/`: HTTP routes (`auth.ts`, `feeds.ts`, `articles.ts`, `youtube.ts`).
  - `backend/src/services/`: integrations (RSS parsing, YouTube, `ytdlp`).
  - `backend/src/db/schema.ts`: Drizzle schema; migrations output to `backend/drizzle/`.
- `ios/`: iOS 17+ SwiftUI app.
  - `ios/FeedFlow/Features/`: UI organized by feature.
  - `ios/FeedFlow/Core/`: networking + services.
  - `ios/FeedFlow/Models/`: SwiftData models.
  - `ios/project.yml`: XcodeGen project spec (preferred for project settings).

## Build, Test, and Development Commands

Backend (run from `backend/`):
- `npm ci` (or `npm install`) — install dependencies.
- `npm run dev` — start local API with hot reload (default `http://localhost:3000`).
- `npm run build` — compile TypeScript to `backend/dist/`.
- `npm start` — run the compiled server.
- `npm run db:generate` / `npm run db:migrate` — generate/apply Drizzle migrations.

iOS:
- Open `ios/FeedFlow.xcodeproj` in Xcode, or regenerate with `xcodegen` from `ios/project.yml`.

## Coding Style & Naming Conventions

- TypeScript: ESM + `strict` TS. Keep imports compatible with build output (relative imports include `.js`, e.g. `../db/index.js`). Prefer small route handlers delegating to `services/`.
- Swift: follow Swift API Design Guidelines. Keep Views in `Features/`, shared logic in `Core/`, and models in `Models/`.

## Testing Guidelines

- No dedicated automated test suite is currently present. Use `npm run build` and a quick smoke check (`GET /health`) for backend changes, and build/run in Xcode for iOS changes.
- If introducing tests, keep them close to the code they cover and document how to run them.

## Commit & Pull Request Guidelines

- Commit messages generally follow an imperative style and often match Conventional Commits: `feat(scope): ...`, `fix: ...`.
- PRs should include: a clear description, linked issues, and screenshots/screen recordings for UI changes. Call out API contract changes and any required DB migrations.

## Configuration & Security Tips

- Backend config uses `backend/.env` (copy from `backend/.env.example`); never commit secrets (DB URLs, JWT/OAuth credentials).
- OAuth relies on URL schemes (`feedflow://` and reversed client ID). If you touch auth flows, verify callbacks on a simulator/device and keep redirect URIs in sync.
