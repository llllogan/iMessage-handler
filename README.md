# Apple Handler

A local macOS Swift monorepo containing two small HTTP services:

- `imessage-handler`: searches Messages data through a read-only source database and an app-owned SQLite/FTS index.
- `calendar-handler`: reads and updates iCloud Calendar data through EventKit.

Both services are designed for local automation and MCP-style access. They bind to localhost by default and can optionally require bearer-token authentication.

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode command line tools
- Full Disk Access for iMessage database reads
- Contacts access for iMessage contact-name lookup
- Calendar access for EventKit calendar reads and writes

## Build And Test

From the repo root:

```sh
swift build
swift test
```

You can also work inside each package directly:

```sh
cd imessage-handler && swift test
cd calendar-handler && swift test
```

## Run The Services

iMessage Handler listens on `127.0.0.1:8080` by default:

```sh
swift run imessage-handler
```

Calendar Handler listens on `127.0.0.1:8090` by default:

```sh
swift run calendar-handler
```

Copy `.env.example` to `.env` for root-level development, or use the `.env.example` inside an individual handler directory when running from that directory.

## Configuration

iMessage settings:

```sh
IMESSAGE_HOST=127.0.0.1
IMESSAGE_PORT=8080
IMESSAGE_DB_PATH=~/Library/Messages/chat.db
IMESSAGE_INDEX_DB_PATH=~/Library/Application Support/imessage-handler/index.sqlite
IMESSAGE_SYNC_INTERVAL_SECONDS=30
IMESSAGE_API_TOKEN=change-me
```

Calendar settings:

```sh
CALENDAR_HOST=127.0.0.1
CALENDAR_PORT=8090
CALENDAR_API_TOKEN=change-me
CALENDAR_DEFAULT_LOOKAHEAD_DAYS=90
```

When `IMESSAGE_API_TOKEN` or `CALENDAR_API_TOKEN` is set, matching `/api/*` requests must include:

```http
Authorization: Bearer change-me
```

## Menu Bar Apps

Each handler still includes its own menu bar app build script:

```sh
cd imessage-handler
scripts/build-menubar-app.sh
open "dist/iMessage Handler.app"
```

```sh
cd calendar-handler
scripts/build-menubar-app.sh
open "dist/Calendar Handler.app"
```

Grant the resulting app the relevant macOS privacy permissions after first launch.

## API Documentation

Detailed API docs remain with each handler:

- [iMessage Handler](imessage-handler/README.md)
- [Calendar Handler](calendar-handler/README.md)
