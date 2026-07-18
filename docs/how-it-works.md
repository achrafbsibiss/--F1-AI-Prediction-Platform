# How the system works

Two processes, one job queue, one model artifact.

- **Rails** owns users, races, entries and stored predictions. It never does
  math on race outcomes.
- **FastAPI** owns the model. It is stateless: it holds no database, no session,
  and no memory of previous requests.

Rails talks to FastAPI over plain HTTP/JSON. Either can be restarted without the
other noticing.

---

## 1. The prediction request

```
Browser                 Rails (Puma)        Sidekiq            FastAPI          Postgres
   |                         |                 |                  |                |
   |-- POST /races/1/prediction -->            |                  |                |
   |                         |-- enqueue ----->|                  |                |
   |<-- 302 redirect --------|                 |                  |                |
   |                         |                 |-- POST /predict/race -->          |
   |                         |                 |<-- probabilities -|                |
   |                         |                 |-- upsert_all ------------------->  |
   |                         |                 |                  |                |
   |<== Turbo Stream replace (via Redis / ActionCable) ===========|                |
```

The HTTP response comes back immediately with a redirect. Nothing waits on the
model. The updated card arrives later over the socket.

### The pieces, in order

| Step | File | Responsibility |
| ---- | ---- | -------------- |
| 1 | [`app/controllers/races/predictions_controller.rb`](../app/controllers/races/predictions_controller.rb) | Authenticates, enqueues the job, redirects |
| 2 | [`app/jobs/generate_race_prediction_job.rb`](../app/jobs/generate_race_prediction_job.rb) | Runs on the `predictions` queue; broadcasts the result |
| 3 | [`app/services/prediction_service.rb`](../app/services/prediction_service.rb) | Builds the payload, persists the response |
| 4 | [`app/services/python_ai_service.rb`](../app/services/python_ai_service.rb) | HTTP client, timeouts, retries |
| 5 | [`ai_service/app/main.py`](../ai_service/app/main.py) | Validates input, calls the model |
| 6 | [`ai_service/models/race_model.py`](../ai_service/models/race_model.py) | Features, inference, normalisation |

---

## 2. Wire format

**Request** — `POST /predict/race`

```json
{
  "race": "Belgian Grand Prix",
  "season": 2026,
  "laps": 44,
  "drivers": [
    { "code": "NOR", "name": "Lando Norris", "grid": 1, "pace": 96.0, "team": "McLaren" }
  ]
}
```

**Response**

```json
{
  "race": "Belgian Grand Prix",
  "model_version": "race-v1",
  "winner": "NOR",
  "win_probabilities":    { "NOR": 0.334, "PIA": 0.294, "...": 0.001 },
  "podium_probabilities": { "NOR": 0.756, "PIA": 0.712, "...": 0.004 }
}
```

Drivers are matched by `code` (`NOR`, `VER`, …) on the way back. Codes are
unique in the `drivers` table.

---

## 3. The model

### Features

Five features per driver, built in `build_features`. Four of the five are
**field-relative** — computed against the rest of that race's entry list, not in
absolute terms. A P5 start means something different in a 20-car field than in a
10-car field, and the model needs to see that.

| Feature | Meaning |
| ------- | ------- |
| `grid` | Starting slot |
| `pace` | 0–100 form rating |
| `grid_rank_pct` | Grid slot as a fraction of the field |
| `pace_gap_to_best` | Gap to the fastest car present |
| `front_row` | 1 if starting P1 or P2 |

`pace` comes from `race_entries.pace_rating`. In training it is derived from each
driver's mean finishing position over the previous five races, shifted by one so
a row never sees its own result. Drivers with no history start at the P10
equivalent.

### Estimator

Two independent `LogisticRegression` classifiers — one for "won", one for
"finished top 3" — inside a `StandardScaler` pipeline.

Logistic regression is a deliberate choice over a tree ensemble. A season
produces roughly 24 winners, so the positive class is tiny. `GradientBoosting`
was tried first and produced a **non-monotonic tail**: a P13 car outranked a P5
car with worse pace. A linear model stays ordered in grid and pace, which
matters more here than squeezing out log-loss.

### Normalisation

Raw classifier scores do not sum to anything meaningful, so `_normalise`
rescales them:

- **Win** probabilities sum to `1.0` — one winner.
- **Podium** probabilities sum to `3.0` — three slots — and are capped at `1.0`
  per driver, with any overflow redistributed across the remaining drivers.

### Retraining

```bash
cd ai_service
python -m training.train_race_model --seasons 2022 2023 2024 2025 2026
```

Bump `MODEL_VERSION` in `race_model.py` when the features or estimator change.
The version is stored on every `predictions` row, so old rows stay attributable
to the model that produced them.

The service loads the artifact lazily on first request and caches it in
`_model`. **Restart uvicorn after retraining** or it keeps serving the old
weights.

---

## 4. Persistence

`PredictionService#persist` writes with `upsert_all` against the unique index
`(race_id, prediction_type, driver_id)`. Re-running a prediction updates the
existing rows in place rather than accumulating history — which is what live
per-lap updates will need, since they rewrite the same rows every lap.

`created_at` is preserved on update; `updated_at` is refreshed by Rails and must
**not** appear in `update_only`, or Postgres rejects the statement with
`multiple assignments to same column`.

To keep a history of how predictions moved during a race, add a separate
append-only table rather than relaxing this index.

---

## 5. Real-time delivery

The show page subscribes:

```erb
<%= turbo_stream_from @race.prediction_stream %>   # "race_<id>_predictions"
```

The job broadcasts a replacement for `race_<id>_prediction_card`, which is the
`id` on the root element of `predictions/_card.html.erb`. The same partial
renders on first page load and on every broadcast, so there is one template to
keep correct.

`prediction_controller.js` animates the bars from zero on connect, which fires
both on initial render and each time Turbo swaps the card in.

**ActionCable runs on Redis in development**, not the `async` adapter. The
broadcast originates in the Sidekiq process; `async` is per-process and would
drop it without an error.

---

## 6. Schema notes

Three deliberate departures from the original spec:

| Spec | Here | Why |
| ---- | ---- | --- |
| `sessions` | `race_sessions` | `Session` collides with Rails' own session concept |
| `sessions.type` | `session_kind` | `type` triggers Single Table Inheritance |
| — | `race_entries` | Grid slot and pace are per race, not per driver |

`race_entries` is the join that makes the model callable: a `Driver` has no grid
position, a `RaceEntry` does.

Enumerated values live in Ruby constants — `Race::STATUSES`,
`RaceSession::KINDS`, `Prediction::TYPES`, `User::ROLES` — validated at the model
layer rather than by database enums.

---

## 7. Failure behaviour

| Failure | Result |
| ------- | ------ |
| FastAPI down | `PythonAiService::Unavailable`; Sidekiq retries 5× with polynomial backoff |
| Model artifact missing | FastAPI returns 503; surfaces as `PythonAiService::Error` |
| Race deleted mid-flight | `discard_on ActiveRecord::RecordNotFound` — no retry |
| Fewer than 2 entries | `ArgumentError` before any HTTP call |
| Unknown driver code in response | That row is skipped; the rest still persist |

Faraday is configured with a 15s read timeout and a 5s open timeout, and retries
twice at the transport layer before the job-level retry takes over.

---

## 8. Extending it

**Another prediction type** (qualifying, sprint):

1. Add the type to `Prediction::TYPES`.
2. Add a model class under `ai_service/models/` and a training script.
3. Add the endpoint to `main.py`.
4. Add a method to `PythonAiService` and a service object beside
   `PredictionService`.

The `predictions` table already carries `prediction_type`, so no migration is
needed.

**Live per-lap updates:** schedule a job on the `live` queue that rebuilds
entries from `laps` and re-runs the pipeline. The upsert and the broadcast
target already handle repeated writes to the same rows.

**Lap-level ingestion:** the `laps` table exists but nothing fills it. The
loader already has the FastF1 session handle; it needs a `session.load(laps=True)`
path and an endpoint alongside the entry-list one.

---

## 9. Data ingestion

Rails cannot call FastF1 — that is Python. So the FastAPI service doubles as the
F1 data gateway, and Rails only maps JSON onto tables.

```
rake f1:race[2026,10]
   → F1DataService
      → PythonAiService#race_entries
         → GET /data/race/2026/10
            → fastf1_loader.race_entry_list
               → FastF1 (cached on disk)
   ← constructors, drivers, circuit, race, race_entries (all upserted)
```

Two endpoints back this:

| Endpoint | Returns |
| -------- | ------- |
| `GET /data/season/{year}` | The calendar — round, name, country, date |
| `GET /data/race/{year}/{round}` | Entry list: driver, team, number, grid slot, form rating |

### Why form is computed in Python

`pace` is not a raw FastF1 field — it is derived (mean finishing position over
the last five races, mapped onto 0–100 by `form_from_mean_finish`). Both the
training frame and the live entry list call **that same function**. If Rails
recomputed it, the two definitions would drift and the model would be scored on
a feature it was never trained on.

### Idempotency

Every write is an upsert on a natural key — `drivers.code`, `(season, round)`,
`(race_id, driver_id)`. Re-importing after qualifying updates grid slots in
place. Drivers no longer on the entry list are removed from that race, so a
mid-season seat swap doesn't leave a ghost entry.

Note that `import_race_entries` reassigns `driver.constructor` on every import:
the schema models a driver's team as a single current value, so a mid-season
move rewrites history. If that matters, move the association onto `RaceEntry`
(which already carries `constructor_id`) and drop it from `Driver`.

### Grid provenance

`races.grid_source` records where the starting order came from, because before
qualifying there is no grid and the loader has to estimate one from form. The
race page renders a warning in that case. A prediction built on an estimated
grid is a much weaker claim than one built on a real grid, and the UI is not
allowed to blur that distinction.
