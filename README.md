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

The first Contacts sync may prompt macOS for Contacts permission.

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

Optional configuration:

```sh
IMESSAGE_PORT=9090 swift run imessage-handler
IMESSAGE_DB_PATH="$HOME/Library/Messages/chat.db" swift run imessage-handler
IMESSAGE_INDEX_DB_PATH="$HOME/Library/Application Support/imessage-handler/index.sqlite" swift run imessage-handler
IMESSAGE_SYNC_INTERVAL_SECONDS=15 swift run imessage-handler
```

## Sync Model

The service does not install triggers or hooks inside Apple's database. That would require modifying `chat.db`, which is risky.

Instead it:

- watches `chat.db`, `chat.db-wal`, and `chat.db-shm` for filesystem changes when those files exist
- debounces file changes and runs an incremental sync
- runs a timer fallback, defaulting to every 30 seconds
- exposes manual sync and rebuild endpoints

The initial background sync indexes messages in batches. For a full clean rebuild, call:

```http
POST http://127.0.0.1:8080/api/index/rebuild
```

## API

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

### `POST /api/contacts/sync`

Reads macOS Contacts and stores phone/email-to-name mappings in the local index DB. This does not modify Contacts or Messages.

Run this after starting the server if you want to search by a person's name:

```http
POST http://127.0.0.1:8080/api/contacts/sync
```

### `GET /api/messages/search`

Recommended endpoint for agents and user-facing search.

Query parameters:

- `person`: optional contact name, phone number, email address, group chat name, or chat identifier
- `phrase`: optional word or phrase to search in decoded message text
- `limit`: optional result limit, default `50`, max `500`
- `offset`: optional pagination offset

Examples:

```http
GET http://127.0.0.1:8080/api/messages/search?person=Julian&limit=50
GET http://127.0.0.1:8080/api/messages/search?phrase=Wordle&limit=50
GET http://127.0.0.1:8080/api/messages/search?person=Julian&phrase=Wordle&limit=50
```

### `GET /api/people`

Looks up synced Contacts identities by name, phone, or email.

```http
GET http://127.0.0.1:8080/api/people?query=Julian&limit=25
```

### `GET /api/messages/recent`

Returns recent messages from the local decoded index. Defaults to 5.

```http
GET http://127.0.0.1:8080/api/messages/recent
GET http://127.0.0.1:8080/api/messages/recent?limit=10
```

### `GET /api/messages`

Returns messages from the local decoded index, newest first.

Query parameters:

- `with`: optional phone number, email, chat identifier, or display-name fragment
- `limit`: optional result limit, default `50`, max `500`
- `offset`: optional pagination offset

```http
GET http://127.0.0.1:8080/api/messages?with=555&limit=50
```

### `GET /api/messages/{messageID}`

Returns one indexed message by stable Messages row ID.

### `GET /api/messages/{messageID}/context`

Returns the target message plus nearby messages from the same conversation.

Query parameters:

- `before`: optional number of prior messages, default `10`, max `500`
- `after`: optional number of following messages, default `10`, max `500`

```http
GET http://127.0.0.1:8080/api/messages/157973/context?before=10&after=10
```

### `GET /api/chats`

Lists indexed conversations, newest first.

Query parameters:

- `query`: optional display name, chat identifier, or participant handle fragment
- `limit`: optional result limit, default `50`, max `500`
- `offset`: optional pagination offset

```http
GET http://127.0.0.1:8080/api/chats?query=Cheap%20Housing&limit=25
```

### `GET /api/chats/{chatID}/summary`

Returns aggregate metadata for one chat: identifiers, message count, first/last message dates, and participants.

### `GET /api/chats/{chatID}/messages`

Returns messages in one chat, newest first.

Query parameters:

- `before`: optional ISO-8601 timestamp upper bound
- `limit`: optional result limit, default `50`, max `500`
- `offset`: optional pagination offset

```http
GET http://127.0.0.1:8080/api/chats/766/messages?limit=50
```

### `GET /api/participants`

Lists indexed participants/handles, newest first.

Query parameters:

- `query`: optional phone/email fragment
- `limit`: optional result limit, default `50`, max `500`
- `offset`: optional pagination offset

### `GET /api/timeline`

Returns messages across all chats in a time window, newest first.

Query parameters:

- `since`: optional ISO-8601 timestamp lower bound
- `until`: optional ISO-8601 timestamp upper bound
- `limit`: optional result limit, default `100`, max `500`
- `offset`: optional pagination offset

```http
GET http://127.0.0.1:8080/api/timeline?since=2026-04-27T00:00:00Z&until=2026-04-29T00:00:00Z&limit=100
```

### `GET /api/search`

Searches the local decoded full-text index.

```http
GET http://127.0.0.1:8080/api/search?query=dinner&limit=50
GET http://127.0.0.1:8080/api/search?query=dinner&with=555&limit=50
```

## Test With HTTP Yak

Open `requests.http` in VS Code and run the requests with the HTTP Yak extension.

## Notes

- Apple's `message.text` column is often empty on newer macOS releases.
- This Swift version attempts to decode `message.attributedBody` with `NSKeyedUnarchiver`.
- Rows that cannot be decoded are still indexed with empty text and `textSource: "undecoded"`.
- The index is an app-owned cache. Deleting `index.sqlite` only removes the derived copy, not Messages data.
