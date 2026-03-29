# ClaudeLifter — Workout Tracker with AI Coach

> A native iOS strength-training app that combines fast workout logging with Claude-powered coaching.

---

## Table of Contents

1. [Overview](#1-overview)
2. [User Stories](#2-user-stories)
3. [Data Model](#3-data-model)
4. [Architecture](#4-architecture)
5. [Feature Specification](#5-feature-specification)
6. [Claude AI Integration](#6-claude-ai-integration)
7. [Azure Backend](#7-azure-backend)
8. [MCP Server](#8-mcp-server)
9. [Exercise Library](#9-exercise-library)
10. [UI/UX Design](#10-uiux-design)
11. [Phasing & Milestones](#11-phasing--milestones)
12. [Cost Estimates](#12-cost-estimates)
13. [Open Decisions](#13-open-decisions)
14. [Reference Material](#14-reference-material)

---

## 1. Overview

### Problem

Existing workout apps (JEFIT, Strong, Hevy) are either subscription-gated, lack AI coaching, or don't allow external tooling (Claude Code, claude.ai) to read and modify workout data. None integrate an LLM as a first-class personal trainer.

### Solution

A native SwiftUI iPhone app for strength training that:
- Logs reps, sets, and weight with minimal friction (≤3 taps per set)
- Provides Claude as an in-app personal trainer with full access to workout history
- Syncs data to Azure for cloud persistence and external access
- Exposes workout data via an MCP server so Claude Code and claude.ai can query and modify workouts without consuming API tokens

### Target User

Single user (Evan). No multi-user, no social features, no App Store distribution planned.

### Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Swift / SwiftUI (iOS 17+) |
| **Local Storage** | SwiftData |
| **Cloud Database** | Azure Cosmos DB (NoSQL, Free Tier) |
| **Image Storage** | Azure Blob Storage (Hot LRS) |
| **API Layer** | Azure Functions (Node.js, Consumption Plan) |
| **AI** | Anthropic API via [SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic) SDK |
| **AI Models** | User-configurable; defaults to claude-haiku-4-5 (routine) and claude-sonnet-4-6 (coaching) |
| **MCP Server** | TypeScript + @modelcontextprotocol/sdk (same pattern as personal_memory) |
| **Exercise Data** | [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (800+ exercises, public domain) |

---

## 2. User Stories

### Core Logging
- **As a user**, I can start a workout from a template (e.g., "Wednesday Push Day") and see the exercises I need to do.
- **As a user**, I can log each set with weight and reps, and the app auto-fills the weight/reps I used last time for that exercise.
- **As a user**, I can add notes to any exercise (including machine settings like seat height, pin position).
- **As a user**, after completing a set, a rest timer starts automatically and chimes when it's up.
- **As a user**, I can see my workout history on a calendar view showing which days I trained.

### Templates
- **As a user**, I can create, edit, and delete workout templates.
- **As a user**, each template contains an ordered list of exercises with default sets/reps/weight.
- **As a user**, I can modify an active workout session (add/remove/reorder exercises) without changing the underlying template.

### Exercises
- **As a user**, I can browse a pre-populated exercise library categorized by muscle group, movement pattern, and equipment.
- **As a user**, I can create custom exercises and assign tags/categories.
- **As a user**, I can add new tag categories beyond the defaults.
- **As a user**, I can attach one photo to an exercise (e.g., a picture of the machine).

### AI Coach
- **As a user**, I can open a chat tab and talk to Claude about my current workout, ask for advice, or request workout modifications.
- **As a user**, Claude can see my workout history and recommend weights based on past performance and time off.
- **As a user**, Claude can build a new workout template or a full multi-day program for me.
- **As a user**, Claude can modify my active workout session (but not the saved template unless I ask).
- **As a user**, I see proactive comments from Claude when I open the app (e.g., "You haven't trained legs in 2 weeks").
- **As a user**, Claude can view the photo attached to an exercise if relevant.

### External Access
- **As a user**, I can use Claude Code or claude.ai to query my workout data, edit templates, and review progress — without consuming Anthropic API tokens beyond my existing Max subscription.

---

## 3. Data Model

### Entity Relationship Diagram (Conceptual)

```
Exercise (Library)
├── id: UUID
├── name: String
├── force: String? (push/pull/static)
├── level: String? (beginner/intermediate/advanced)
├── mechanic: String? (compound/isolation)
├── equipment: String? (barbell/dumbbell/machine/cable/bodyweight/...)
├── instructions: [String]
├── imageURL: String? (bundled asset or blob URL)
├── photoURL: String? (user-taken photo, blob URL)
├── notes: String?
├── tags: [ExerciseTag]
├── isCustom: Bool
├── primaryMuscles: [String]
└── secondaryMuscles: [String]

ExerciseTag
├── id: UUID
├── category: String (e.g., "muscle_group", "equipment", "movement_pattern", or custom)
└── value: String (e.g., "chest", "barbell", "horizontal_push")

WorkoutTemplate
├── id: UUID
├── name: String (e.g., "Wednesday Push Day")
├── notes: String?
├── createdAt: Date
├── updatedAt: Date
├── lastPerformedAt: Date?
├── timesPerformed: Int
└── exercises: [TemplateExercise] (ordered)

TemplateExercise
├── id: UUID
├── order: Int
├── exercise: Exercise (reference)
├── defaultSets: Int
├── defaultReps: Int
├── defaultWeight: Double?
├── defaultRestSeconds: Int (default: 90)
└── notes: String?

Workout (Logged Session)
├── id: UUID
├── templateId: UUID? (which template it was started from)
├── name: String
├── startedAt: Date
├── completedAt: Date?
├── notes: String?
├── syncStatus: SyncStatus (.pending/.synced)
├── lastModified: Date
└── exercises: [WorkoutExercise] (ordered)

WorkoutExercise
├── id: UUID
├── order: Int
├── exercise: Exercise (reference)
├── notes: String?
├── restSeconds: Int
└── sets: [WorkoutSet] (ordered)

WorkoutSet
├── id: UUID
├── order: Int
├── weight: Double?
├── weightUnit: WeightUnit (.kg/.lbs)
├── reps: Int?
├── isCompleted: Bool
├── completedAt: Date?
└── notes: String?

AIChatMessage
├── id: UUID
├── workoutId: UUID? (if during active workout)
├── role: MessageRole (.user/.assistant/.system)
├── content: String
├── timestamp: Date
└── syncStatus: SyncStatus

ProactiveInsight
├── id: UUID
├── content: String
├── generatedAt: Date
├── isRead: Bool
└── type: InsightType (.suggestion/.warning/.encouragement)

TrainingPreference
├── id: UUID
├── key: String (e.g., "exercise_order", "injury", "training_style")
├── value: String (e.g., "compounds before isolation", "bad left shoulder")
├── createdAt: Date
├── updatedAt: Date
└── source: String? ("user_stated" / "claude_inferred")
```

### Key Design Decisions

- **Template vs. Session separation**: Modifying an active workout does NOT modify the template. Templates are blueprints; sessions are instances.
- **Auto-fill**: When starting a workout from a template, each exercise's most recent logged weight/reps (from the last session using the same exercise) are pre-populated into the set fields.
- **Weight unit**: Stored per-set so mixed kg/lbs usage is possible. User sets a global default preference.
- **Notes for machine settings**: Machine-specific settings (seat height, pin position, etc.) are stored as free-text notes on the Exercise or WorkoutExercise level rather than structured fields, since machines vary too much.
- **SyncStatus**: Tracks whether each record has been synced to Azure. Enables offline-capable logging with deferred sync.

---

## 4. Architecture

### System Diagram

```
┌─────────────────────────────────────────────────────┐
│                    iPhone App                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ Workout  │  │ Exercise │  │   Chat   │          │
│  │  Tab     │  │  Library │  │   Tab    │          │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       │              │              │                │
│  ┌────┴──────────────┴──────────────┴─────┐         │
│  │            SwiftData (Local)            │         │
│  └────────────────┬───────────────────────┘         │
│                   │                                  │
│  ┌────────────────┴───────────────────────┐         │
│  │           Sync Manager                  │         │
│  │  (NWPathMonitor + background tasks)     │         │
│  └────────┬──────────────────┬────────────┘         │
└───────────┼──────────────────┼──────────────────────┘
            │                  │
            ▼                  ▼
┌───────────────────┐  ┌──────────────────┐
│  Azure Functions  │  │  Anthropic API   │
│  (REST API)       │  │  (via proxy AF)  │
│  ┌─────────────┐  │  └──────────────────┘
│  │  Cosmos DB  │  │
│  │  (Free Tier)│  │
│  ├─────────────┤  │
│  │ Blob Storage│  │
│  │  (Images)   │  │
│  └─────────────┘  │
└────────┬──────────┘
         │
         ▼
┌──────────────────────────┐
│  MCP Server (stdio)      │
│  ├── Claude Code         │
│  └── claude.ai           │
│  (reads/writes same      │
│   Cosmos DB + Blob data) │
└──────────────────────────┘
```

### Key Architectural Decisions

1. **SwiftData as source of truth for the UI.** All reads/writes hit SwiftData first for instant responsiveness.
2. **Azure Functions as API gateway.** The iPhone app never talks directly to Cosmos DB or Blob Storage. Functions handle auth, validation, and Anthropic API proxying (so the API key stays server-side).
3. **Anthropic API key proxied through Azure Functions.** The SwiftUI app calls an Azure Function endpoint (e.g., `POST /api/chat`), which forwards to the Anthropic API. The API key is stored as an Azure Function app setting, never on the device.
4. **MCP server for Claude Code / claude.ai access.** A separate MCP server (following the same pattern as personal_memory) connects to the same Cosmos DB and Blob Storage. This allows Claude Code to query workout history, create templates, and modify data — all using Max subscription tokens instead of API billing.
5. **Sync strategy: last-write-wins.** Since this is a single-user app, conflicts are resolved by timestamp. The Sync Manager tracks `lastModified` and `syncStatus` on each record.
6. **Azure resource consolidation.** Shares the same Azure subscription as personal_memory. New resource group `rg-workout-app-prod` in `westeurope`. Could potentially share the storage account for blob images, but separate Cosmos DB account to use its own free tier allocation.

---

## 5. Feature Specification

### 5.1 Workout Logging

#### Starting a Workout
1. User taps a template from the home screen (e.g., "Wednesday Push Day").
2. App creates a new `Workout` session linked to that template.
3. For each exercise in the template, the app looks up the **most recent completed session** containing that exercise and pre-fills:
   - The weight used last time
   - The reps performed last time
4. User sees a scrollable list of exercises, each showing its sets with pre-filled weight/reps.

#### Logging a Set
1. User adjusts weight and/or reps if needed (number steppers or direct input).
2. User taps the set row or a checkmark to mark it complete.
3. The `completedAt` timestamp is recorded.
4. The rest timer starts automatically.

#### Rest Timer
- Default rest period configurable per exercise (default: 90 seconds).
- Displays as a countdown in the app.
- **Live Activity** on Lock Screen and Dynamic Island so the timer works when the phone is locked.
- Chime + haptic feedback when time is up.
- Quick-adjust buttons: +15s, -15s.
- User can dismiss/skip the timer.

#### Completing a Workout
1. User taps "Finish Workout."
2. `completedAt` is set on the Workout.
3. Summary screen shows: exercises completed, total sets, total volume, any PRs hit.
4. Workout is queued for sync to Azure.

#### Modifying an Active Workout
- User can add exercises (search the library), remove exercises, or reorder them.
- These modifications apply **only to the active session**, not the template.
- If the user wants to update the template, that's a separate explicit action.

### 5.2 Templates

- CRUD operations on workout templates.
- Each template has a name, ordered list of exercises, and per-exercise defaults (sets, reps, weight, rest time).
- Templates can be created manually, or generated by Claude.
- A "Save Session as Template" action lets the user promote an ad-hoc or modified session into a new template.

### 5.3 Exercise Library

- Pre-populated with ~800 exercises from [free-exercise-db](https://github.com/yuhonas/free-exercise-db).
- Each exercise has: name, primary/secondary muscles, equipment, force type, difficulty level, mechanic type, instructions, and static images.
- **Tagging system**: Exercises have tags organized by categories. Default categories:
  - `muscle_group` (chest, back, shoulders, biceps, triceps, quadriceps, hamstrings, glutes, calves, abs, forearms)
  - `equipment` (barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, smith_machine, etc.)
  - `movement_pattern` (horizontal_push, horizontal_pull, vertical_push, vertical_pull, hip_hinge, squat, lunge, carry, rotation)
  - `force` (push, pull, static)
  - `mechanic` (compound, isolation)
  - `level` (beginner, intermediate, advanced)
- Users can create **custom tag categories** and add tags freely.
- Users can create **custom exercises**.
- One user-taken photo per exercise (stored in Azure Blob Storage).

### 5.4 Calendar View

- Monthly calendar showing which days have logged workouts.
- Intensity indicated by color saturation (like GitHub contribution graph):
  - No workout: empty
  - Light workout (few sets): light color
  - Heavy workout (many sets): dark color
- Tapping a day shows a summary of that day's workout(s).
- Weekly workout count visible at a glance.

### 5.5 History & Progress

- **History list**: Chronological list of past workouts, most recent first. Filterable by template, exercise, or date range.
- **Per-exercise history**: When viewing an exercise, see all past sets for that exercise over time.
- **PR detection**: Automatically detect and highlight personal records (heaviest weight, most reps at a given weight, highest estimated 1RM via Brzycki formula).
- **Charts** (future enhancement): Volume over time, 1RM progression per exercise, muscle group distribution. Use Swift Charts.

---

## 6. Claude AI Integration

### 6.1 Chat Tab

A dedicated tab with a chat interface for conversing with Claude.

**Context available to Claude:**
- The active workout session (if any) — exercises, sets logged so far, template name
- Historical workout data — retrieved on-demand via tool use, not bulk-loaded
- Exercise library metadata
- Exercise photos (via vision, when user asks about a specific machine)
- User preferences (weight unit, training goals, etc.)

**System prompt structure:**
```
[CACHED — static, ~90% cache hit savings]
- Role: Expert personal trainer and exercise scientist
- Domain knowledge: progressive overload, periodization, rep ranges, RPE, recovery
- Output format rules
- Tool definitions

[DYNAMIC — appended per request]
- Current active workout state (if any)
- Recent proactive insights context
- User's message
```

**Tools available to Claude (in-app):**
| Tool | Description |
|------|------------|
| `get_exercise_history` | Get past sets for a given exercise (last N sessions or date range) |
| `get_recent_workouts` | Get summaries of recent workouts (last N days/sessions) |
| `get_workout_detail` | Get full detail of a specific past workout |
| `get_exercise_info` | Get exercise metadata, instructions, and photo |
| `add_exercise_to_workout` | Add an exercise to the active session |
| `remove_exercise_from_workout` | Remove an exercise from the active session |
| `reorder_exercises` | Reorder exercises in the active session |
| `suggest_weight` | Calculate recommended weight based on history and time off |
| `create_template` | Create a new workout template |
| `create_program` | Create multiple templates forming a training program |

**Model selection:**
- Default routing: `claude-haiku-4-5` for routine queries, `claude-sonnet-4-6` for coaching
- **User-configurable in Settings:** The user can override which model is used for each task category (routine queries, coaching, proactive insights) or set a single model for all tasks. The app should support any current Anthropic model (Haiku, Sonnet, Opus) and be easy to update when new models release. A "Model" picker in Settings lists available models with their relative cost indicator ($, $$, $$$).

**Cost controls:**
- Prompt caching on the static system prompt (~2K tokens cached)
- Haiku default for ≥70% of interactions (user can override)
- Full conversation history within session (no truncation). Chat resets on session end. Training preferences persist across sessions via `TrainingPreference` entity.
- Token budget tracking displayed to user (optional)

### 6.2 Proactive Insights

Generated periodically (e.g., when the app is opened after >24h since last open):
- "You haven't trained legs in 12 days."
- "Your bench press has gone up 5kg over the last month — nice progression."
- "You've been resting 3+ minutes between sets on curls. Consider shortening to 60-90s for hypertrophy."

**Implementation:**
- On app open, check if insights should be generated (time-based throttle).
- Send a lightweight Haiku request with a summary of recent workout stats.
- Display insights as a banner/card on the home screen, dismissable.
- Insights are marked as read when dismissed.

### 6.3 Guardrails: Template vs. Session Modification

| Action | Via Chat | Requires Confirmation |
|--------|----------|-----------------------|
| Modify active workout session | Yes | No (immediate) |
| Create new template | Yes | Yes ("Save this as a template?") |
| Modify existing template | Yes, only if user explicitly asks | Yes ("Update the template?") |
| Delete template | No | N/A |
| Create training program | Yes | Yes ("Save these N templates?") |

---

## 7. Azure Backend

### 7.1 Resource Group & Services

| Resource | Name | SKU/Tier | Est. Cost |
|----------|------|----------|-----------|
| Resource Group | `rg-workout-app-prod` | — | $0 |
| Cosmos DB Account | `cosmos-workout-prod` | NoSQL, Free Tier (1000 RU/s, 25 GB) | $0 |
| Storage Account | `stworkout{suffix}` | Standard LRS, Hot | ~$0.02/mo |
| Function App | `func-workout-prod` | Consumption (Y1), Node.js 20 | $0 |
| Application Insights | `ai-workout-prod` | — | $0 (free tier) |

**Region:** `westeurope` (same as personal_memory)

### 7.2 Cosmos DB Schema

**Database:** `workout-db`

**Containers:**

| Container | Partition Key | Documents |
|-----------|--------------|-----------|
| `exercises` | `/id` | Exercise library (custom exercises only; bundled exercises stay in app) |
| `templates` | `/id` | Workout templates with nested exercise references |
| `workouts` | `/id` | Logged workout sessions with nested exercises and sets |
| `chat` | `/workoutId` | AI chat messages, partitioned by workout session |
| `insights` | `/id` | Proactive insights |

### 7.3 Blob Storage

**Container:** `workout-images`

**Path convention:** `exercises/{exerciseId}.jpg`

**Access pattern:**
1. App requests a SAS token from Azure Function (`GET /api/images/sas?path=exercises/{id}.jpg`)
2. Azure Function generates a time-limited, scoped SAS token
3. App uploads/downloads directly to/from Blob Storage using the SAS URL

### 7.4 Azure Functions API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/sync/pull` | POST | Pull changes since last sync timestamp |
| `/api/sync/push` | POST | Push local changes to Cosmos DB |
| `/api/images/sas` | GET | Generate SAS token for image upload/download |
| `/api/chat` | POST | Proxy to Anthropic API (streams response) |
| `/api/insights` | POST | Generate proactive insights via Haiku |
| `/api/health` | GET | Health check |

**Authentication:** Since this is a single-user personal app, use a shared secret (API key) stored on device and validated by the Function. No OAuth needed. The API key is rotatable via Azure Function app settings.

### 7.5 Sync Flow

```
App Launch
  → Load from SwiftData (instant UI)
  → Check connectivity (NWPathMonitor)
  → If online:
      1. Pull: POST /api/sync/pull { lastSyncTimestamp }
         → Server returns all records modified after that timestamp
         → Merge into SwiftData (last-write-wins by lastModified)
      2. Push: POST /api/sync/push { records[] }
         → Server upserts into Cosmos DB
         → Mark local records as .synced
  → Update lastSyncTimestamp
```

**Background sync:** Use `BGAppRefreshTask` for periodic sync when app is backgrounded.

---

## 8. MCP Server

### Purpose

Allow Claude Code and claude.ai to query and modify workout data directly, using Max subscription tokens instead of API billing.

### Architecture

Follow the same pattern as `personal_memory`:
- TypeScript + `@modelcontextprotocol/sdk`
- Stdio transport for Claude Code
- Connects to the same Cosmos DB and Blob Storage as the app
- Uses `DefaultAzureCredential` for Azure auth

### MCP Tools

| Tool | Description |
|------|------------|
| `list_templates` | List all workout templates |
| `get_template` | Get a template with its exercises |
| `create_template` | Create a new workout template |
| `update_template` | Modify a template |
| `delete_template` | Delete a template |
| `list_workouts` | List workout sessions (with date filtering) |
| `get_workout` | Get full workout detail (exercises, sets, weights) |
| `get_exercise_history` | Get historical data for a specific exercise |
| `search_exercises` | Search exercise library by name, muscle group, equipment |
| `get_stats` | Get summary statistics (PRs, volume trends, frequency) |
| `get_calendar` | Get workout frequency data for a date range |
| `create_program` | Create a multi-day training program (multiple templates) |

### Configuration (Claude Code)

```json
{
  "mcpServers": {
    "workout": {
      "command": "node",
      "args": ["dist/server.js"],
      "cwd": "/path/to/workout-mcp",
      "env": {
        "AZURE_STORAGE_ACCOUNT_URL": "https://stworkout{suffix}.blob.core.windows.net",
        "COSMOS_DB_ENDPOINT": "https://cosmos-workout-prod.documents.azure.com",
        "COSMOS_DB_DATABASE": "workout-db"
      }
    }
  }
}
```

---

## 9. Exercise Library

### Source

[free-exercise-db](https://github.com/yuhonas/free-exercise-db) — 800+ exercises, public domain.

### Bundling Strategy

- The full exercise JSON is bundled into the app at build time.
- On first launch, exercises are imported into SwiftData with `isCustom = false`.
- Bundled exercises are read-only (user cannot delete/modify them, only add tags/photos/notes).
- Custom exercises created by the user have `isCustom = true`.
- Only custom exercises are synced to Cosmos DB. Bundled exercises are always loaded from the app bundle.

### Images

- free-exercise-db includes static images (2 per exercise: start and end positions).
- These are bundled as app assets.
- Animated GIFs are out of scope for MVP (would require licensing or custom creation).

---

## 10. UI/UX Design

### Tab Bar Structure

| Tab | Icon | Content |
|-----|------|---------|
| **Home** | house | Active workout or template picker + proactive insights |
| **History** | calendar | Calendar heatmap + workout history list |
| **Exercises** | dumbbell | Exercise library browser |
| **Coach** | message bubble | Claude chat interface |

### Key Screens

#### Home (No Active Workout)
- Proactive insight cards (dismissable)
- "Start Workout" button → template picker
- Quick stats: workouts this week, current streak

#### Home (Active Workout)
- Workout name and timer (elapsed)
- List of exercises with sets
- Each set row: [weight field] × [reps field] [checkmark]
- Pre-filled with last session's values (shown in lighter text until edited)
- Completed sets have a filled checkmark and subtle highlight
- Rest timer overlay when active (countdown + skip button)
- "Add Exercise" button at bottom
- "Finish Workout" button

#### Template Picker
- List of templates with name and last-performed date
- Swipe to edit/delete
- "New Template" button (manual or "Ask Claude to build one")

#### Exercise Library
- Search bar
- Filter chips by tag category (muscle group, equipment, etc.)
- Exercise card: name, primary muscles, equipment icon
- Exercise detail: instructions, images, user photo, notes, history

#### Calendar / History
- Monthly calendar with colored dots/intensity
- Below calendar: list of workouts for selected day/month
- Workout detail: full set-by-set breakdown

#### Coach (Chat)
- Standard chat UI (messages, input field, send button)
- Context indicator: "Chatting about: Wednesday Push Day" or "General"
- Streaming responses
- Tool-use actions shown as compact cards ("Added Incline DB Press to your workout")

### Design Principles (from JEFIT/Strong/Hevy research)

1. **≤3 taps to log a set.** Weight and reps are pre-filled; user only taps the checkmark in the happy path.
2. **Auto-fill previous values.** Last session's weight/reps shown as defaults. This is the single most important UX feature.
3. **Haptic feedback** on set completion and timer events.
4. **Large tap targets.** Gym use means sweaty hands, gloves, imprecise tapping.
5. **Dark mode default.** Easier on the eyes in gym lighting.

---

## 11. Phasing & Milestones

### Phase 1 — MVP: Local App + Claude Chat

**Goal:** A usable workout tracker with AI coaching, all running locally + Anthropic API.

| Feature | Details |
|---------|---------|
| SwiftData models | All entities from §3 |
| Exercise library | Bundled from free-exercise-db, browsable with search and tag filters |
| Template CRUD | Create, edit, delete workout templates |
| Workout logging | Start from template, log sets with auto-fill, mark complete |
| Rest timer | In-app countdown with chime + haptics (Live Activities deferred) |
| Claude chat | Dedicated tab, Anthropic API via direct HTTPS (API key on device for Phase 1) |
| Claude tools | `get_exercise_history`, `get_recent_workouts`, `suggest_weight`, `add_exercise_to_workout`, `remove_exercise_from_workout` |
| Basic history | List of past workouts, per-exercise history |
| Weight unit | Global kg/lbs preference, per-set override |

**Deferred to Phase 2:** Cloud sync, image storage, calendar heatmap, MCP server, proactive insights.

**Note on API key in Phase 1:** Storing the API key on-device is acceptable for a personal app not distributed via App Store. It moves server-side in Phase 2.

### Phase 2 — Cloud Sync + Images

**Goal:** Data persisted in Azure. Photos supported. Calendar view.

| Feature | Details |
|---------|---------|
| Azure Functions API | `/sync/pull`, `/sync/push`, `/images/sas`, `/chat` (proxy) |
| Cosmos DB | All data synced |
| Blob Storage | Exercise photos (one per exercise) |
| Sync Manager | Automatic sync on connectivity, background refresh |
| API key proxy | Anthropic API key moves from device to Azure Function |
| Calendar heatmap | Monthly view with intensity shading |
| Photo capture | Camera integration to photograph machines |

### Phase 3 — MCP Server + Advanced AI

**Goal:** External access via MCP. Richer AI features.

| Feature | Details |
|---------|---------|
| MCP server | TypeScript, stdio transport, full CRUD on templates/workouts |
| Proactive insights | Haiku-generated insights on app open |
| Claude template/program generation | Create templates and multi-day programs via chat |
| Template modification via chat | With confirmation guardrail |
| Live Activities | Rest timer on Lock Screen and Dynamic Island |
| PR detection | Automatic personal record tracking and celebration |
| Charts | Swift Charts for volume/1RM/frequency trends |

---

## 12. Cost Estimates

### Monthly Recurring (Post Phase 2)

| Item | Cost |
|------|------|
| Azure Cosmos DB (Free Tier) | $0 |
| Azure Functions (Consumption) | $0 |
| Azure Blob Storage (~1 GB images) | $0.02 |
| Azure data transfer (outbound) | $0 |
| Application Insights | $0 |
| **Azure subtotal** | **~$0.02** |
| Anthropic API (Haiku + Sonnet, est. usage) | ~$1–3 |
| **Total** | **~$1–3/month** |

### Anthropic API Cost Breakdown (Estimated)

| Usage | Model | Tokens/Month | Cost |
|-------|-------|-------------|------|
| Routine queries (5/session × 12 sessions) | Haiku | ~120K in + 60K out | ~$0.10 |
| Coaching conversations (3/week) | Sonnet | ~90K in + 45K out | ~$0.70 |
| Proactive insights (12/month) | Haiku | ~36K in + 12K out | ~$0.03 |
| Prompt cache writes | — | — | ~$0.15 |
| **API subtotal** | | | **~$1.00** |

Well within the $3/month budget. Actual costs will depend on conversation length and frequency.

---

## 13. Open Decisions

| # | Decision | Options | Notes |
|---|----------|---------|-------|
| 1 | ~~App name~~ | **Resolved: ClaudeLifter** | — |
| 2 | ~~Infra-as-code~~ | **Resolved: Bicep** (consistent with personal_memory) | — |
| 3 | ~~Azure Functions language~~ | **Resolved: TypeScript** (consistent with personal_memory + MCP server) | — |
| 4 | ~~Share storage account?~~ | **Resolved: Dedicated storage account** (`stworkout{suffix}`) | — |
| 5 | ~~Weight unit default~~ | **Resolved: kg** (changeable in settings) | — |
| 6 | ~~Rest timer default~~ | **Resolved: 90 seconds** (configurable per exercise) | — |
| 7 | ~~Chat history retention~~ | **Resolved: Per-session reset + persistent preferences.** Full chat history within a session (no truncation/summarization). Chat clears on session end. Training preferences ("I prefer compounds before isolation", "bad left shoulder — avoid overhead pressing") saved to a persistent preference store and loaded into system prompt each session. | — |
| 8 | ~~Proactive insights frequency~~ | **Resolved: Every app open, but Phase 3 feature only.** | — |

---

## 14. Reference Material

### Open Source References

| Repo | Stars | Why It's Relevant |
|------|-------|-------------------|
| [kabouzeid/Iron](https://github.com/kabouzeid/Iron) | 206 | SwiftUI weightlifting tracker — closest architectural reference |
| [karthironald/BodyProgress](https://github.com/karthironald/BodyProgress) | 272 | SwiftUI + CoreData workout app — UI patterns |
| [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) | 1,219 | Exercise database (800+ exercises, public domain JSON) |
| [wger-project/wger](https://github.com/wger-project/wger) | 5,870 | Mature data model reference |
| [jamesrochabrun/SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic) | 235 | Swift SDK for Anthropic API |
| [Zacharysp/CalendarHeatmap](https://github.com/Zacharysp/CalendarHeatmap) | 212 | Calendar heatmap component |
| [astashov/liftosaur](https://github.com/astashov/liftosaur) | 541 | Template/routine system reference |

### AI Integration References

| Source | Pattern |
|--------|---------|
| [Nate Tang's AI Fitness Coach](https://medium.com/@natetang) | SQL-based tool use for workout history retrieval |
| [Smart Rabbit Fitness](https://smartrabbitfitness.com) | 3,000-line expert system prompt, program generation |
| [WHOOP AI Studio](https://engineering.prod.whoop.com/ai-studio/) | Inline tools, pre-injected context |
| [serverless-ai-fitness](https://github.com/allenheltondev/serverless-ai-fitness) | AWS serverless workout generation, response caching |

### Azure Architecture References

| Topic | Key Finding |
|-------|------------|
| Cosmos DB Free Tier | 1000 RU/s + 25 GB, lifetime free, provisioned throughput only |
| Blob upload pattern | SAS tokens generated server-side, direct upload from device |
| SwiftData sync | Custom sync layer with lastModified + syncStatus, last-write-wins |
| No official Swift Azure SDK | Use Azure Functions as REST API gateway instead |
| SwiftAnthropic | Community SDK, 235 stars, supports streaming/vision/tools/caching |
