# داده‌یار — Persian Flutter web frontend

A Material 3 workspace for the existing Dataset Agent API. All operations use real REST endpoints; there is no mock data or browser-side model key.

## Start

Start the API from the repository root:

```powershell
$env:DATA_AGENT_BROWSER_ORIGINS='["http://localhost:8080","http://127.0.0.1:8080"]'
.\.venv\Scripts\agent-dataset.exe
```

From this directory:

```powershell
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 8080
```

Use the connection settings button to change the API URL or supply a project Bearer token. The API default can also be built with `--dart-define=API_BASE_URL=https://api.example.com`. Use HTTPS for both UI and API in a remote deployment. The server's origin allowlist must include the frontend's exact scheme, hostname, and port. `localhost` and `127.0.0.1` are distinct origins.

## Workflow

1. Upload a supported table or document and wait for ingestion.
2. Select a version in the dataset list. Tables display 20 rows per page, with zero-based row positions.
3. Click a cell to edit its JSON scalar value: `"تهران"`, `42`, `true`, or `null`. Add a row using a JSON object or delete a row. Each operation creates a child version; return to an older version through the list.
4. Use the transformation form for cleanup, filtering, sorting, renaming, type conversion, dropping columns, or multiplication into a new column. The agent/API supports additional transformations and arithmetic operators.
5. Ask questions in Persian, inspect computed evidence, generate HTML reports, or download a selected version as CSV, JSON, XLSX, or Parquet.

Model keys belong in the server environment. Offline mode profiles tables and retrieves document keywords; arbitrary Persian requests require a configured model. Direct edits work in offline mode. New selections and direct edits start a fresh chat; versions created within an agent run remain in that conversation's scope. Progress and cancellation apply to upload/chat/report jobs; synchronous tool operations use the API timeout.

## Verify and build

```powershell
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
```

Serve `build/web` through an HTTP server. The build bundles Flutter's renderer and the [Vazirmatn font](https://github.com/rastikerdar/vazirmatn), whose SIL OFL license is included in `assets/fonts/OFL.txt`. The FastAPI backend is a separate process; the static app does not embed it. This project has not been published to a hosting service.

Implementation references: [Flutter localization](https://docs.flutter.dev/ui/internationalization), [Flutter web builds](https://docs.flutter.dev/platform-integration/web/building), and [FastAPI CORS](https://fastapi.tiangolo.com/tutorial/cors/).
