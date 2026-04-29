# Calendar Handler

A local macOS HTTP API for reading and updating iCloud Calendar data through Apple's EventKit framework.

This service does not read Calendar databases directly. It uses `EKEventStore`, so the Mac running it must be signed into iCloud and have Calendar sync enabled.

## Run Locally

```sh
swift run calendar-handler
```

The API listens on:

```text
http://127.0.0.1:8090
```

Optional configuration can be supplied with shell env vars or a `.env` file copied from `.env.example`:

```sh
CALENDAR_PORT=8090 swift run calendar-handler
CALENDAR_API_TOKEN="long-random-token" swift run calendar-handler
```

When `CALENDAR_API_TOKEN` is set, every `/api/*` request must include:

```http
Authorization: Bearer long-random-token
```

## Menu Bar App

Build and run the background menu bar app:

```sh
scripts/build-menubar-app.sh
open "dist/Calendar Handler.app"
```

The app starts the same HTTP server as the CLI and includes menu actions for:

- Request Calendar Access
- Sync Status
- Open Calendar Privacy Settings
- Quit

Grant Calendar access to the built app when macOS prompts. If needed, open:

```text
System Settings > Privacy & Security > Calendars
```

## API

### `GET /healthz`

Checks that the process is running.

### `GET /api/access/status`

Returns the current EventKit authorization status.

### `POST /api/access/request`

Requests full Calendar access.

### `GET /api/calendars`

Lists calendars visible to EventKit.

### `GET /api/events/range`

Returns events between two dates.

Query parameters:

- `since`: lower bound as `YYYY-MM-DD`, ISO-8601, or Unix timestamp
- `until`: upper bound as `YYYY-MM-DD`, ISO-8601, or Unix timestamp
- `calendarID`: optional EventKit calendar identifier
- `calendar`: optional calendar title substring
- `limit`: default `100`, max `1000`
- `offset`: default `0`

### `GET /api/events/search`

Searches events using weighted keyword matching over title, location, notes, calendar title, and URL.

Query parameters:

- `query`: required search text
- `since`, `until`, `calendarID`, `calendar`, `limit`, `offset`: same as range

### `GET /api/events/{eventID}`

Returns one event by EventKit identifier.

### `GET /api/free-time`

Finds open slots between events.

Query parameters:

- `since`, `until`: search window
- `durationMinutes`: default `30`
- `calendarID`, `calendar`: optional filters

### `POST /api/events/create`

Creates a calendar event. JSON body:

```json
{
  "title": "Dentist",
  "start": "2026-04-29T09:00:00+10:00",
  "end": "2026-04-29T10:00:00+10:00",
  "calendarID": "...",
  "location": "Brisbane",
  "notes": "Bring forms",
  "url": "https://example.com",
  "isAllDay": false
}
```
