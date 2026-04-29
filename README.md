# iMessage Handler

A local Swift API for searching macOS Messages history without modifying Apple's Messages database.

The service opens `~/Library/Messages/chat.db` read-only, decodes message bodies into plain text, and stores the decoded copy in its own SQLite/FTS index:

```text
~/Library/Application Support/imessage-handler/index.sqlite
```

Searches run against that local index, not directly against Apple's database.

## Requirements

- macOS
- Swift 6 / Xcode command line tools
- Full Disk Access for the terminal app or VS Code if it launches the server
- Contacts access for the terminal app or VS Code if you want person-name lookup

To grant access, open **System Settings** > **Privacy & Security** > **Full Disk Access**, enable your terminal app or VS Code, then restart that app.

On startup, the server requests Contacts permission and, if granted, syncs Contacts into the local index in the background.

## Run Locally

Build:

```sh
swift build
```

Run:

```sh
swift run imessage-handler
```

The API listens on:

```text
http://127.0.0.1:8080
```

## Menu Bar App

You can also run iMessage Handler as a background macOS menu bar app:

```sh
scripts/build-menubar-app.sh
open "dist/iMessage Handler.app"
```

The app starts the same HTTP server as the CLI, shows status from the menu bar, and includes menu actions for:

- Sync Now
- Rebuild Index
- Open Full Disk Access Settings
- Quit

For Messages database access, grant Full Disk Access to the built app:

```text
System Settings > Privacy & Security > Full Disk Access > iMessage Handler
```

If you rebuild or move the `.app`, macOS may require you to grant access again. The CLI remains available for development with `swift run imessage-handler`.

Optional configuration:

```sh
IMESSAGE_PORT=9090 swift run imessage-handler
IMESSAGE_DB_PATH="$HOME/Library/Messages/chat.db" swift run imessage-handler
IMESSAGE_INDEX_DB_PATH="$HOME/Library/Application Support/imessage-handler/index.sqlite" swift run imessage-handler
IMESSAGE_SYNC_INTERVAL_SECONDS=15 swift run imessage-handler
IMESSAGE_API_TOKEN="long-random-token" swift run imessage-handler
```

You can also copy `.env.example` to `.env` and run `swift run imessage-handler`. Values already exported in your shell take priority over `.env`.

For the menu bar app, config is loaded from these locations when present:

- `.env` in the current working directory
- `~/Library/Application Support/imessage-handler/.env`
- `.env` bundled into `iMessage Handler.app/Contents/Resources`

The build script copies the repo `.env` into the generated app bundle if it exists.

When `IMESSAGE_API_TOKEN` is set, every `/api/*` request must include:

```http
Authorization: Bearer long-random-token
```

## Sync Model

The service does not install triggers or hooks inside Apple's database. That would require modifying `chat.db`, which is risky.

Instead it:

- watches `chat.db`, `chat.db-wal`, and `chat.db-shm` for filesystem changes when those files exist
- debounces file changes and runs an incremental sync
- runs a timer fallback, defaulting to every 30 seconds
- exposes admin endpoints for operational checks, manual sync, and rebuilds

The initial background sync indexes messages in batches. For a full clean rebuild, call:

```http
POST http://127.0.0.1:8080/api/index/rebuild
```

## API

The API is intentionally small for MCP use. An MCP server should search for likely messages, then fetch nearby conversation context for any promising hit before answering the user.

### `GET /healthz`

Checks that the process is running.

### `GET /api/messages/count`

Returns the number of rows in Apple's `message` table.

### `GET /api/index/status`

Returns source count, indexed count, index path, source path, and the last indexed message row id.

### `GET /api/index/stats`

Returns aggregate counts showing how many indexed rows came from `message.text`, `message.attributedBody`, had no source body, or failed decoding.

### `POST /api/index/sync`

Indexes messages with `ROWID` greater than the highest row already indexed.

### `POST /api/index/rebuild`

Deletes the local index and rebuilds it from Apple's read-only database.

### `GET /api/messages/search`

Finds candidate messages from the local decoded index.

Query parameters:

- `person`: contact name, phone number, email address, group chat name, or chat identifier
- `phrase`: word or phrase to search in decoded message text
- `since`: optional inclusive lower date bound, as `YYYY-MM-DD`, ISO-8601, or Unix timestamp
- `until`: optional inclusive upper date bound, as `YYYY-MM-DD`, ISO-8601, or Unix timestamp
- `timeframe`: optional relative range: `today`, `yesterday`, `this_week`, `last_week`, `this_month`, `last_month`, `last_7_days`, `last_14_days`, `last_30_days`, or `last_90_days`
- `mode`: optional text search mode for `phrase`, default `ranked`
  - `ranked`: weighted keyword search using SQLite FTS5 BM25 relevance
  - `exact`: exact phrase search
  - `all`: every search term must match
  - `any`: at least one search term must match
- `limit`: optional result limit, default `50`, max `500`
- `offset`: optional pagination offset

At least one of `person`, `phrase`, `since`, `until`, or `timeframe` is required.

Examples:

```http
GET http://127.0.0.1:8080/api/messages/search?person=Julian&limit=50
GET http://127.0.0.1:8080/api/messages/search?phrase=Wordle&limit=50
GET http://127.0.0.1:8080/api/messages/search?person=Julian&phrase=Wordle&limit=50
GET http://127.0.0.1:8080/api/messages/search?person=Julian&timeframe=last_week&limit=50
GET http://127.0.0.1:8080/api/messages/search?phrase=school%20pickup%20time&mode=ranked&limit=50
GET http://127.0.0.1:8080/api/messages/search?phrase=school%20pickup%20time&mode=exact&limit=50
GET http://127.0.0.1:8080/api/messages/search?phrase=flight&since=2026-04-01&until=2026-04-28
```

### `GET /api/messages/{messageID}/context`

Returns the target message plus nearby messages from the same conversation.

Query parameters:

- `before`: optional number of prior messages, default `10`, max `500`
- `after`: optional number of following messages, default `10`, max `500`

```http
GET http://127.0.0.1:8080/api/messages/157973/context?before=10&after=10
```

## Test With HTTP Yak

Open `requests.http` in VS Code and run the requests with the HTTP Yak extension.

## Notes

- Apple's `message.text` column is often empty on newer macOS releases.
- This Swift version attempts to decode `message.attributedBody` with `NSKeyedUnarchiver`.
- Rows that cannot be decoded are still indexed with empty text and `textSource: "undecoded"`.
- The index is an app-owned cache. Deleting `index.sqlite` only removes the derived copy, not Messages data.
