# Life Automation Shortcuts — Design Document

## Overview

Extend Alexander OS (JARVIS) with 6 cross-service automation categories that turn the assistant from a command executor into a proactive life operating system. JARVIS becomes the connective tissue between services that don't talk to each other natively.

## Architecture: Hybrid Approach

iOS-native for Apple APIs (HealthKit, EventKit, MediaPlayer, HomeKit, Focus modes). Relay adapters in Node.js for external services (Noom, MyChart, Spotify, Skylight, AT&T WiFi, financial services, weather). A synthesis layer on iOS merges both data streams for analysis, insights, and proactive actions.

```
┌─────────────────────────────────────────────┐
│  Mac: Service Bridge (Node.js)              │
│                                             │
│  ┌──────────┐ ┌──────────┐ ┌─────────────┐ │
│  │ WhatsApp │ │  Noom    │ │  Spotify    │ │
│  │ Adapter  │ │ Adapter  │ │  Adapter    │ │
│  └────┬─────┘ └────┬─────┘ └──────┬──────┘ │
│       │             │              │        │
│  ┌──────────┐ ┌──────────┐ ┌─────────────┐ │
│  │ MyChart  │ │ Skylight │ │ AT&T WiFi   │ │
│  │ Adapter  │ │ Adapter  │ │  Adapter    │ │
│  └────┬─────┘ └────┬─────┘ └──────┬──────┘ │
│       │             │              │        │
│  ┌──────────┐ ┌──────────┐ ┌─────────────┐ │
│  │ Weather  │ │Financial │ │  Netflix    │ │
│  │ Adapter  │ │ Adapter  │ │  Adapter    │ │
│  └────┬─────┘ └────┬─────┘ └──────┬──────┘ │
│       │             │              │        │
│       └─────────────┼──────────────┘        │
│                     ▼                       │
│          Adapter Manager + WebSocket        │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  iOS: Alexander OS                          │
│                                             │
│  Native APIs: HealthKit, EventKit,          │
│  MediaPlayer, HomeKit, Focus, Location      │
│                                             │
│  DataAggregator → InsightEngine →           │
│  ProactiveScheduler → Executors             │
└─────────────────────────────────────────────┘
```

## Foundation: Service Adapter Framework

### Relay Side

```
whatsapp-relay/src/
  adapters/
    base-adapter.ts        # Abstract: poll(), authenticate(), normalize()
    noom-adapter.ts
    mychart-adapter.ts
    spotify-adapter.ts
    skylight-adapter.ts
    att-wifi-adapter.ts
    weather-adapter.ts
    financial-adapter.ts
    netflix-adapter.ts
    adapter-manager.ts     # Registers adapters, runs poll schedules
  types.ts                 # Extended with new message types per adapter
```

Each adapter:
- Owns its auth credentials (`.env` or encrypted secrets file)
- Polls on a configurable schedule
- Normalizes data into domain-specific typed messages
- Sends over the existing WebSocket to iOS
- Can receive commands from iOS (bidirectional)

### iOS Side

New synthesis layer (DataAggregator) as an SPM package or within ExecutionEngine:
- Receives relay adapter data via RelayConnection
- Queries native APIs (HealthKit, EventKit, etc.) directly
- Stores domain data in MemorySystem with tags
- Exposes unified query methods per domain

### New IntentActions

Expand from 22 to ~32 cases:

```swift
// Health (expand existing queryHealth)
case getHealthBriefing

// Media
case playMedia, recommendMedia, searchMedia

// Parenting
case checkChores, grantWifi, pauseWifi

// Financial
case getSpendingSummary, checkBudget

// Home Intelligence (extends existing HomeKit actions)
case getHomeStatus, setAutomationRule

// Productivity
case getDayBriefing, blockFocusTime
```

GBNF grammar updates to include all new action values.

## Category 1: Health Command Center

### Data Sources

| Source | Access | Data |
|--------|--------|------|
| Apple Health | HealthKit (iOS native) | Sleep, steps, HR, HRV, workouts, weight, blood pressure |
| Noom | Relay adapter (API/scraping) | Calories, macros, meal timing, food log, weight goal progress |
| MyChart | Relay adapter (FHIR API via Open Epic) | Lab results, medications, upcoming appointments, provider messages |

### Flows

**Morning Health Briefing** (proactive, daily)
- HealthKit: sleep duration + quality, resting HR, HRV
- Noom: yesterday's calorie total vs. budget, weight trend
- MyChart: new lab results or provider messages
- Synthesized and sent to WhatsApp

**Conversational: "How's my health?"**
- 7-day rolling averages from all 3 sources
- Trend detection (improving/declining)
- Cross-source correlation: "Sleep worse on nights you ate after 9pm"

**Pre-Appointment Prep**
- Recent labs, current medications, health trends
- Formatted summary for doctor visits

**Anomaly Alerts** (proactive)
- Resting HR spike, missed Noom logging 2+ days, lab result outside normal range

### Technical Notes

- Noom: no public API. Best path is leveraging Noom's Apple Health integration to pull nutrition data through HealthKit. Fallback: reverse-engineer mobile API.
- MyChart: Epic's Open FHIR API (patient-facing) with OAuth2. Endpoints for labs, medications, conditions, appointments.

## Category 2: Media Intelligence Engine

### Data Sources

| Source | Access | Data |
|--------|--------|------|
| Spotify | Relay adapter (Web API, OAuth2) | Listening history, playlists, saved tracks, playback control |
| Apple Podcasts | iOS native (limited) | Subscriptions, listening history |
| Netflix | Relay adapter (scraping, no official API) | Viewing history, watchlist |
| Hulu/others | Relay adapter (scraping) | Viewing history |

### Flows

**Conversational: "What should I watch/listen to?"**
- Cross-platform taste profile
- Theme/mood identification across platforms
- Context-aware: time, day, who's home

**Weekly Discovery Digest** (proactive)
- Consumption summary across all platforms
- 3 cross-platform recommendations

**Family Movie Night**
- Household taste consideration, age-appropriate filtering

**Content Recall: "What was that podcast about...?"**
- Cross-platform history search

### Technical Notes

- Spotify Web API is excellent. Full listening history, recommendation engine, playback control.
- Netflix/Hulu have no official APIs. Weakest link. Options: web scraping, browser automation, or user self-reporting.

## Category 3: Parenting Accountability System

### Data Sources

| Source | Access | Data |
|--------|--------|------|
| Skylight | Relay adapter (API/scraping) | Chore list per kid, completion status, streaks |
| AT&T Smart Home WiFi | Relay adapter (API) | Profile management, pause/unpause per profile |

### Flows

**Auto-Gate** (proactive, polling)
- Skylight adapter checks chore completion every X minutes
- Rule engine: "If Kid A's chores not done by 4pm, pause Kid A's WiFi profile"
- Auto-unpause when completed
- Parent notified via WhatsApp

**Manual Override** (conversational, requires confirmation)
- "Give [kid] WiFi for an hour" — timed exception
- "Pause everyone's WiFi" — immediate lockdown

**Parent Dashboard** (conversational)
- Per-kid chore completion, WiFi status, streaks

**Weekly Report** (proactive)
- Completion rates, WiFi hours, trends per kid

**Positive Reinforcement**
- Configurable reward rules: early completion → bonus WiFi time

### Technical Notes

- AT&T Smart Home Manager: reverse-engineer web API or find local router management API. SNMP is a fallback if supported.
- Skylight: investigate API availability; web scraping of the calendar app as fallback.

## Category 4: Financial Pulse

### Data Sources

| Source | Access | Data |
|--------|--------|------|
| Banking | Relay adapter (Plaid API) | Transactions, balances, pending charges |
| Budget tool | Relay adapter (YNAB API) | Categories, spending vs. budget, goals |

### Flows

**Daily Spend Check-in** (proactive, evening)
- Day's transactions, category breakdown, budget status

**Conversational: "Can I afford X?"**
- Checks category budget + upcoming bills

**Bill Anomaly Alert** (proactive)
- Significant increase vs. historical average

**Subscription Audit** (proactive, monthly)
- Active subscriptions, total cost, usage patterns

### Security

Financial data requires strong encryption at rest, minimal data retention, and explicit user opt-in. Credentials handled via Plaid Link (token-based, no raw bank credentials stored).

## Category 5: Home Intelligence

### Data Sources

| Source | Access | Data |
|--------|--------|------|
| HomeKit | iOS native (already built) | Devices, states, scenes |
| Weather | Relay adapter (OpenWeatherMap/WeatherKit) | Forecast, conditions, alerts |
| Calendar | iOS native (already built) | Events, guests |
| Energy | Relay adapter (utility API/smart meter) | Usage, costs |

### Flows

**Weather-Reactive Automation** (proactive)
- Cold snap → pre-heat. Rain → close windows reminder. UV high → sunscreen nudge.

**Calendar-Aware Scenes** (proactive)
- Dinner party → entertaining scene pre-activated
- Work meeting → office scene + Focus mode

**Anomaly Detection** (proactive)
- Door unlocked too long, lights on in empty rooms, garage open late

**Energy Optimization** (conversational + proactive)
- Usage insights, ventilation suggestions, monthly trends

## Category 6: Productivity Orchestrator

### Data Sources

| Source | Access | Data |
|--------|--------|------|
| Calendar | iOS native (already built) | Meetings, free time blocks |
| Reminders | iOS native (already built) | Tasks, due dates, overdue |
| Focus Modes | iOS native | Mode switching, automation |

### Flows

**Morning Briefing** (proactive, daily)
- Meetings, deep work blocks, overdue tasks, weather

**Smart Time Blocking** (conversational)
- "I need to call the dentist" → finds gap, creates calendar block

**Auto Focus Modes** (proactive)
- Meeting → DND. Deep work → Work Focus. End of day → Personal.

**End of Day Review** (proactive, evening)
- Completed vs. rolled tasks, tomorrow preview

## Interaction Model

All 6 categories support two interaction modes:

**Conversational (via WhatsApp)**
- Natural language queries processed through the existing LLM pipeline
- New intent actions routed to domain-specific executors

**Proactive (JARVIS-initiated)**
- ProactiveScheduler runs on iOS, triggered by:
  - Time-based schedules (morning briefing, evening review)
  - Relay adapter events (chore completed, anomaly detected)
  - Native API events (HealthKit background delivery, calendar changes)
- Proactive messages sent to WhatsApp via relay

## Implementation Priority

Recommended build order based on API availability, user impact, and foundation reuse:

1. **Adapter Framework** — BaseAdapter, AdapterManager, DataAggregator, ProactiveScheduler
2. **Productivity Orchestrator** — Uses only iOS-native APIs, no relay adapters needed
3. **Home Intelligence** — Extends existing HomeKit, adds weather adapter
4. **Health Command Center** — HealthKit native + Noom/MyChart adapters
5. **Parenting Accountability** — Skylight + AT&T WiFi adapters
6. **Media Intelligence** — Spotify adapter + Netflix scraping (most complex data sources)
7. **Financial Pulse** — Plaid integration (most sensitive, needs careful security)

## Confirmation Policy Updates

High-risk actions requiring confirmation:
- `pauseWifi`, `grantWifi` (affects kids' access)
- `blockFocusTime` (modifies calendar)
- `setAutomationRule` (changes home behavior)
- Financial queries above a sensitivity threshold

## Open Questions for Implementation

1. Noom data access: HealthKit integration vs. reverse-engineering their API?
2. Netflix/Hulu: accept limited scraping or rely on user self-reporting?
3. AT&T Smart Home WiFi: API availability needs investigation
4. Skylight: API availability needs investigation
5. Financial services: which bank/budgeting tool to target first?
6. Proactive message frequency: how often is helpful vs. annoying?
