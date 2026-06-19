# CalmVault — Copilot Instructions

## Repository Structure

CalmVault is organized as a **hands-on deployment lab**. Each `activity-N/` folder is an incremental addition containing only new or modified files for that stage.

```
activity-1/          ← Deploy infrastructure + run locally
  backend/       ← Express + TypeScript REST API
    Dockerfile   ← Backend API container (node:20-alpine)
  frontend/      ← Vue 3 + TypeScript SPA (Vite)
    Dockerfile   ← Frontend SPA container (nginx:alpine → port 8080)
  infrastructure/← Bicep templates for Azure
activity-2/          ← Add ACR + build container images (no local Docker)
  infrastructure/← Bicep with ACR added
  nginx.conf     ← nginx config for SPA routing + API proxy
activity-3/          ← Deploy to Azure Container Apps
  infrastructure/← Split Bicep: backend.main.bicep + frontend.main.bicep
activity-4/          ← Add monitoring and observability
  infrastructure/← Diagnostic settings for Storage, Cosmos DB, ACR
activity-5/          ← AI auto-tagging with GPT-4o (optional)
  tagger/        ← TypeScript queue-polling app (Event Grid → GPT-4o → Cosmos)
  infrastructure/← Azure OpenAI, Event Grid, Storage Queue, Tagger Container App
activity-6/          ← Clean up all Azure resources
```

The root `DEPLOYMENT_GUIDE.md` is the primary walkthrough for the lab.

## Architecture

- **`activity-1/backend/`** — Express + TypeScript REST API (Node.js). Handles file uploads, metadata CRUD, and proxies Azure services. Runs on port 3001.
- **`activity-1/frontend/`** — Vue 3 + TypeScript SPA (Vite). Communicates with the backend via `fetch` calls in `src/services/api.ts`. Runs on port 5173.
- **`activity-1/infrastructure/`** — Bicep templates for Azure deployment. `main.bicep` is the subscription-level entry point; `resources.bicep` is a module scoped to the resource group.
- **`activity-3/infrastructure/`** — Split into `backend.main.bicep` (deploys Log Analytics, Container Apps Environment, backend app) and `frontend.main.bicep` (deploys frontend app). Backend is deployed first so its URL can be passed to the frontend image build.
- **`activity-4/infrastructure/`** — Adds diagnostic settings that send logs and metrics from Storage (Blob), Cosmos DB, and Container Registry to the existing Log Analytics workspace. Also creates an Azure Dashboard with KQL-powered panels for file uploads, downloads, and Cosmos DB activity.
- **`activity-5/tagger/`** — TypeScript Container App Job that processes queue messages from Event Grid blob-created events, downloads the file, sends it to Azure OpenAI GPT-4o for analysis, and updates Cosmos DB with `ai:`-prefixed tags. Runs as event-driven job executions (0→5) triggered by queue length.
- **`activity-5/infrastructure/`** — Deploys Azure OpenAI (GPT-4o), Event Grid system topic + subscription, Storage Queue, and the tagger Container App Job.

Files are stored in **Azure Blob Storage**. Metadata and tags are stored in **Azure Cosmos DB** (serverless). There is no authentication (MVP).

### Data flow

1. User uploads a file → frontend sends `multipart/form-data` to `POST /api/files`
2. Backend receives the file via `multer` (memory storage), uploads the buffer to Azure Blob Storage, then writes metadata to Cosmos DB
3. Tags are stored as a `string[]` on the Cosmos DB document — no separate tags collection
4. File downloads are proxied through the backend (`GET /api/files/:id/download`), not served directly from Blob Storage

### Key types

The `FileMetadata` interface is the central data model, defined in both:
- `activity-1/backend/src/models/file.ts`
- `activity-1/frontend/src/types/file.ts`

These must stay in sync manually. If you add a field to one, add it to the other.

## Build & Run Commands

### Backend (`cd activity-1/backend`)

| Command            | Description                        |
| ------------------ | ---------------------------------- |
| `npm run dev`      | Start with hot reload (`tsx watch`)|
| `npm run build`    | Compile TypeScript to `dist/`      |
| `npm run start`    | Run compiled output                |
| `npm run typecheck`| Type-check without emitting        |

### Frontend (`cd activity-1/frontend`)

| Command            | Description                        |
| ------------------ | ---------------------------------- |
| `npm run dev`      | Start Vite dev server              |
| `npm run build`    | Type-check + production build      |
| `npm run preview`  | Preview production build           |

### Infrastructure (`cd activity-1/infrastructure`)

```bash
az deployment group create --resource-group $RG_NAME --template-file activity-1/infrastructure/main.bicep --name activity1-main
```

All resource names follow the pattern `calmvault-<resource>-<suffix>` (or `calmvault<suffix>` for storage accounts, which disallow hyphens). The suffix is the user identifier derived from the lab login (e.g., `user1`). Resource groups are pre-created with the pattern `rg-calmvault-<suffix>-usc`.

### Infrastructure Components

Defined in `main.bicep` (resource-group scope, delegates to `resources.bicep`):

| Resource | Type | Name Pattern | Notes |
| --- | --- | --- | --- |
| Resource Group | `Microsoft.Resources/resourceGroups` | `rg-calmvault-<suffix>-usc` | Pre-created by lab admin |
| Storage Account | `Microsoft.Storage/storageAccounts` | `calmvault<suffix>` | Standard LRS, TLS 1.2, no public blob access, shared key access enabled |
| Blob Container | `storageAccounts/blobServices/containers` | `calmvault-files` | Created inside the storage account |
| Cosmos DB Account | `Microsoft.DocumentDB/databaseAccounts` | `calmvault-cosmos-<suffix>` | Serverless mode, Session consistency, local auth enabled |
| Cosmos DB Database | `databaseAccounts/sqlDatabases` | `calmvault` | SQL API |
| Cosmos DB Container | `sqlDatabases/containers` | `files` | Partition key: `/id` |
| Container Registry | `Microsoft.ContainerRegistry/registries` | `calmvaultacr<suffix>` | Basic SKU, admin user enabled (added in activity-2) |
| Log Analytics | `Microsoft.OperationalInsights/workspaces` | `calmvault-logs-<suffix>` | 30-day retention (added in activity-3) |
| Container Apps Env | `Microsoft.App/managedEnvironments` | `calmvault-env-<suffix>` | Linked to Log Analytics (added in activity-3) |
| Backend Container App | `Microsoft.App/containerApps` | `calmvault-backend-<suffix>` | Port 3001, external ingress, 0–3 replicas (added in activity-3) |
| Frontend Container App | `Microsoft.App/containerApps` | `calmvault-frontend-<suffix>` | Port 8080, external ingress, 0–3 replicas (added in activity-3) |
| Diagnostic Setting (Storage Blob) | `Microsoft.Insights/diagnosticSettings` | `calmvault<suffix>-blob-diag` | Blob read/write/delete logs + transaction metrics (added in activity-4) |
| Diagnostic Setting (Cosmos DB) | `Microsoft.Insights/diagnosticSettings` | `calmvault-cosmos-<suffix>-diag` | Data plane requests, query stats, partition key stats (added in activity-4) |
| Diagnostic Setting (ACR) | `Microsoft.Insights/diagnosticSettings` | `calmvaultacr<suffix>-diag` | Repository events, login events + all metrics (added in activity-4) |
| Azure Dashboard | `Microsoft.Portal/dashboards` | `calmvault-dashboard-<suffix>` | 4 metric chart panels: storage transactions, Cosmos requests, Cosmos by status, storage availability (added in activity-4) |
| Application Insights | `Microsoft.Insights/components` | `calmvault-insights-<suffix>` | App-level telemetry linked to Log Analytics, auto-collects requests/dependencies/exceptions (added in activity-4) |
| Azure OpenAI | `Microsoft.CognitiveServices/accounts` | `calmvault-openai-<suffix>` | S0 SKU, GPT-4o model deployed with 10K TPM (added in activity-5) |
| Storage Queue | `storageAccounts/queueServices/queues` | `blob-events` | Receives Event Grid blob-created events for tagger processing (added in activity-5) |
| Event Grid System Topic | `Microsoft.EventGrid/systemTopics` | `calmvault-storage-events-<suffix>` | Watches Storage Account for BlobCreated events (added in activity-5) |
| Tagger Container App Job | `Microsoft.App/jobs` | `calmvault-tagger-<suffix>` | Event-driven job, scales 0→5 executions based on queue length, runs GPT-4o tagging (added in activity-5) |

### Environment

Backend requires a `.env` file (copy from `.env.example`) with Azure Blob Storage and Cosmos DB credentials. After deploying infrastructure, populate `.env` from the Bicep outputs. Secrets (connection strings, keys) are not included in Bicep outputs — retrieve them via the Azure CLI after deployment.

Frontend uses `VITE_API_BASE_URL` (defaults to `http://localhost:3001`).

## Conventions

### Backend patterns

- **Service layer separation**: Route handlers in `src/routes/` call service functions in `src/services/`. Routes handle HTTP concerns (status codes, request parsing); services handle business logic and Azure SDK calls.
- **Azure SDK initialization**: `initCosmos()` and `initBlobStorage()` are called once at startup in `src/index.ts`. Service modules export getter functions (e.g., `getFilesContainer()`) that throw if called before init.
- **Application Insights**: Instrumented at the top of `src/index.ts` using `require('applicationinsights')` inside a conditional block (before other imports). Auto-collects HTTP requests, dependencies, exceptions, and performance counters. Enabled only when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set.
- **Express route handlers** return `Promise<void>` and set response status explicitly. Do not return response objects.
- **Error handling**: Each route wraps its body in try/catch and returns a JSON error with appropriate status code.
- **Blob naming**: Uploaded files are stored with a UUID + original extension as the blob name (not the original filename) to avoid collisions.

### Frontend patterns

- **API client**: All backend calls go through `src/services/api.ts`. Do not use `fetch` directly in components.
- **Type sharing**: `src/types/file.ts` mirrors the backend's `FileMetadata` interface.
- **Component style**: All components use `<script setup lang="ts">` with Composition API. Props use `defineProps<{}>()`, emits use `defineEmits<{}>()`.
- **State management**: App-level state lives in `App.vue` using `ref()` and `computed()` — no Pinia/Vuex. State is passed down via props; mutations flow up via emits.
- **Component responsibilities**:
  - `App.vue` — owns all state (`files`, `allTags`, `selectedTag`), handles API calls for CRUD, passes data down to children
  - `AppHeader.vue` — branding + upload button, emits `upload` and `toggle-sidebar`
  - `TagSidebar.vue` — tag filter list, emits `select` with tag name or `null` for "All Files"
  - `FileGallery.vue` — grid/list view toggle, renders `FileCard` instances
  - `FileCard.vue` — display-only, emits `click` (preview) and `delete`
  - `FileUpload.vue` — drag & drop + file picker, calls `api.uploadFiles()` directly, emits `upload-complete`
  - `FilePreview.vue` — modal overlay, uses `TagEditor` for inline tag editing, emits `close`, `delete`, `tags-updated`
  - `TagEditor.vue` — reusable tag chip input, uses `update:tags` emit pattern (v-model compatible)
- **CSS**: Scoped styles per component. Global design tokens in `style.css` using CSS custom properties (`--color-*`, `--space-*`, `--text-*`). No CSS framework.
- **File icons**: MIME-type-to-emoji mapping in `FileCard.vue` (`fileIcon()` function). Image thumbnails use `api.getDownloadUrl(id)`.
- **Delete confirmation**: Uses `window.confirm()` in `App.vue` before calling the API.
- **Tags**: Always lowercased and trimmed before saving. Backspace in an empty tag input removes the last tag.

### Lab authoring

- **Pause for architectural tradeoffs.** When multiple valid approaches exist for a new feature (e.g., Container Apps vs Container App Jobs, polling vs event-driven, queue vs webhook), stop and present the options with pros/cons before implementing. Do not commit to an architecture without confirmation.
- **Target audience**: 100–200 level developers. Assume familiarity with basic CLI usage and web development concepts, but do NOT assume knowledge of Azure services, Bicep, Docker, or infrastructure-as-code. Explain "why" alongside "what" for Azure-specific concepts.
- Each activity folder (`activity-N/`) is an **incremental addition** — it contains only new or modified files for that stage. Earlier activities remain unchanged.
- The root `DEPLOYMENT_GUIDE.md` provides the lab walkthrough. Keep it in sync when adding new activities.
- Every infrastructure or code change must be reflected in `DEPLOYMENT_GUIDE.md`, the activity README, and `.github/copilot-instructions.md`.
- Dockerfiles live alongside their source code (`activity-1/backend/Dockerfile`, `activity-1/frontend/Dockerfile`) but the build context is the repo root.
- **Dual-platform commands**: All CLI command blocks in READMEs and the deployment guide must include both Bash and PowerShell equivalents. Use **Bash:** / **PowerShell:** labels before each block. For commands identical in both shells, use a single block labeled **Bash / PowerShell:**.
- **Documentation tone**: Brief explanatory notes after commands (what just happened, what to expect). Include expected output where helpful. Add "> **Tip:**" callouts for common pitfalls.
- Minimal, calm design language applies to documentation as well — clear headings, short paragraphs, no clutter.

### Design philosophy

- Minimal, calm, iCloud-inspired UI — lots of whitespace, soft colors (accent: `#5ba4cf`)
- Tag-based organization only (no folder hierarchy)
- Upload limit: 50 MB per file (enforced by multer in `activity-1/backend/src/middleware/upload.ts`)
- Responsive: sidebar collapses to a slide-in menu on mobile (≤768px)

### Conventions

- **Resource naming**: All Azure resources follow `calmvault-<resource>-<suffix>` (or `calmvault<suffix>` for storage accounts). The suffix is the user identifier derived from the lab login (e.g., `user1`). Resource groups are pre-created as `rg-calmvault-<suffix>-usc`.
- **Commit messages**: Imperative mood, concise subject line. Include `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` trailer when Copilot authored the commit.
- **Bicep patterns**: Resource-group-scoped `main.bicep` derives the suffix from the resource group name (`split(resourceGroup().name, '-')[2]`) and delegates to `resources.bicep`. Use `existing` keyword for resources created in prior activities.
- **Secrets handling**: Never output secrets in Bicep outputs. Retrieve keys via Azure CLI after deployment. Pass secrets to Container Apps via the `secrets` array with `secretRef` in env vars.
- **TypeScript style**: Strict mode, ES2022 target, CommonJS modules. Use `tsx` for dev, `tsc` for production builds.
- **Package management**: Use `npm ci` in Dockerfiles for reproducible builds. Use `npm install` locally.
