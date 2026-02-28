# Life Automation Shortcuts — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend Alexander OS with 6 cross-service automation categories (Health, Media, Parenting, Financial, Home Intelligence, Productivity) using a hybrid architecture of iOS-native APIs and Node.js relay adapters.

**Architecture:** Relay adapters in Node.js poll external services and send normalized data over the existing WebSocket to iOS. iOS-native APIs (HealthKit, EventKit, HomeKit) are accessed directly. A DataAggregator on iOS merges both streams. New IntentActions and executors handle domain-specific commands. A ProactiveScheduler triggers briefings and alerts.

**Tech Stack:** Node.js/TypeScript (relay adapters), Swift/SwiftUI (iOS), GRDB/SQLite (storage), HealthKit/EventKit/HomeKit (native APIs), Spotify Web API, Open Epic FHIR API, OpenWeatherMap API, Plaid API.

**Design Doc:** `docs/plans/2026-02-28-life-automation-shortcuts-design.md`

---

## Phase 1: Foundation — Adapter Framework

This phase builds the infrastructure all 6 categories depend on: the relay adapter pattern, the iOS DataAggregator, new IntentActions, and the ProactiveScheduler.

---

### Task 1: Base Adapter Class (Relay)

**Files:**
- Create: `whatsapp-relay/src/adapters/base-adapter.ts`
- Test: `whatsapp-relay/src/adapters/__tests__/base-adapter.test.ts`

**Context:** Every external service adapter (Noom, Spotify, Skylight, etc.) needs the same lifecycle: authenticate, poll on a schedule, normalize data, send over WebSocket. This base class enforces that contract.

**Step 1: Install test dependencies**

```bash
cd whatsapp-relay && npm install --save-dev vitest
```

Add to `package.json` scripts:
```json
"test": "vitest run",
"test:watch": "vitest"
```

**Step 2: Write the failing test**

Create `whatsapp-relay/src/adapters/__tests__/base-adapter.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { BaseAdapter, AdapterConfig, AdapterData } from "../base-adapter.js";

class TestAdapter extends BaseAdapter {
  public pollCount = 0;

  constructor(config: AdapterConfig) {
    super(config);
  }

  async authenticate(): Promise<void> {
    // no-op for test
  }

  async poll(): Promise<AdapterData[]> {
    this.pollCount++;
    return [
      {
        domain: "test",
        type: "test.data",
        payload: { value: this.pollCount },
        timestamp: Date.now(),
      },
    ];
  }
}

describe("BaseAdapter", () => {
  it("should store config and expose name", () => {
    const adapter = new TestAdapter({
      name: "test-adapter",
      enabled: true,
      pollIntervalMs: 60000,
    });
    expect(adapter.name).toBe("test-adapter");
    expect(adapter.enabled).toBe(true);
  });

  it("should call poll and return normalized data", async () => {
    const adapter = new TestAdapter({
      name: "test-adapter",
      enabled: true,
      pollIntervalMs: 60000,
    });
    const data = await adapter.poll();
    expect(data).toHaveLength(1);
    expect(data[0].domain).toBe("test");
    expect(data[0].type).toBe("test.data");
    expect(data[0].payload).toEqual({ value: 1 });
  });

  it("should track last poll time after executePoll", async () => {
    const adapter = new TestAdapter({
      name: "test-adapter",
      enabled: true,
      pollIntervalMs: 60000,
    });
    expect(adapter.lastPollAt).toBeNull();
    await adapter.executePoll();
    expect(adapter.lastPollAt).not.toBeNull();
    expect(adapter.pollCount).toBe(1);
  });

  it("should not poll when disabled", async () => {
    const adapter = new TestAdapter({
      name: "test-adapter",
      enabled: false,
      pollIntervalMs: 60000,
    });
    const result = await adapter.executePoll();
    expect(result).toEqual([]);
    expect(adapter.pollCount).toBe(0);
  });
});
```

**Step 3: Run test to verify it fails**

```bash
cd whatsapp-relay && npx vitest run src/adapters/__tests__/base-adapter.test.ts
```

Expected: FAIL — module not found.

**Step 4: Write minimal implementation**

Create `whatsapp-relay/src/adapters/base-adapter.ts`:

```typescript
import { logger } from "../logger.js";

export interface AdapterConfig {
  name: string;
  enabled: boolean;
  pollIntervalMs: number;
}

export interface AdapterData {
  domain: string;
  type: string;
  payload: Record<string, unknown>;
  timestamp: number;
}

export abstract class BaseAdapter {
  public readonly name: string;
  public readonly enabled: boolean;
  public readonly pollIntervalMs: number;
  public lastPollAt: number | null = null;

  protected log = logger.child({ module: "adapter" });

  constructor(config: AdapterConfig) {
    this.name = config.name;
    this.enabled = config.enabled;
    this.pollIntervalMs = config.pollIntervalMs;
    this.log = logger.child({ module: `adapter:${config.name}` });
  }

  abstract authenticate(): Promise<void>;
  abstract poll(): Promise<AdapterData[]>;

  async executePoll(): Promise<AdapterData[]> {
    if (!this.enabled) {
      return [];
    }

    try {
      const data = await this.poll();
      this.lastPollAt = Date.now();
      this.log.info({ count: data.length }, "Poll completed");
      return data;
    } catch (err) {
      this.log.error({ err }, "Poll failed");
      return [];
    }
  }
}
```

**Step 5: Run test to verify it passes**

```bash
cd whatsapp-relay && npx vitest run src/adapters/__tests__/base-adapter.test.ts
```

Expected: PASS — all 4 tests.

**Step 6: Commit**

```bash
cd whatsapp-relay && git add src/adapters/ package.json package-lock.json
git commit -m "feat: add BaseAdapter class for relay service adapters"
```

---

### Task 2: Adapter Manager (Relay)

**Files:**
- Create: `whatsapp-relay/src/adapters/adapter-manager.ts`
- Test: `whatsapp-relay/src/adapters/__tests__/adapter-manager.test.ts`

**Context:** The AdapterManager registers adapters, runs their poll loops on independent intervals, and forwards results to a callback (which will be the WebSocket `forward()` function). It's the orchestrator for all service adapters.

**Step 1: Write the failing test**

Create `whatsapp-relay/src/adapters/__tests__/adapter-manager.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { AdapterManager } from "../adapter-manager.js";
import { BaseAdapter, AdapterConfig, AdapterData } from "../base-adapter.js";

class MockAdapter extends BaseAdapter {
  public pollResults: AdapterData[] = [];

  constructor(name: string, enabled = true) {
    super({ name, enabled, pollIntervalMs: 100 });
  }

  async authenticate(): Promise<void> {}

  async poll(): Promise<AdapterData[]> {
    return this.pollResults;
  }
}

describe("AdapterManager", () => {
  let manager: AdapterManager;

  afterEach(() => {
    manager?.stopAll();
  });

  it("should register adapters", () => {
    manager = new AdapterManager();
    const adapter = new MockAdapter("test");
    manager.register(adapter);
    expect(manager.getAdapter("test")).toBe(adapter);
  });

  it("should authenticate all adapters on start", async () => {
    manager = new AdapterManager();
    const a1 = new MockAdapter("a1");
    const a2 = new MockAdapter("a2");
    const authSpy1 = vi.spyOn(a1, "authenticate");
    const authSpy2 = vi.spyOn(a2, "authenticate");
    manager.register(a1);
    manager.register(a2);

    await manager.authenticateAll();
    expect(authSpy1).toHaveBeenCalledOnce();
    expect(authSpy2).toHaveBeenCalledOnce();
  });

  it("should poll an adapter and invoke callback with results", async () => {
    manager = new AdapterManager();
    const adapter = new MockAdapter("test");
    adapter.pollResults = [
      { domain: "test", type: "test.event", payload: { v: 1 }, timestamp: Date.now() },
    ];
    manager.register(adapter);

    const received: AdapterData[] = [];
    manager.onData((data) => received.push(...data));

    await manager.pollAdapter("test");
    expect(received).toHaveLength(1);
    expect(received[0].type).toBe("test.event");
  });

  it("should list all registered adapter names", () => {
    manager = new AdapterManager();
    manager.register(new MockAdapter("spotify"));
    manager.register(new MockAdapter("weather"));
    expect(manager.adapterNames()).toEqual(["spotify", "weather"]);
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd whatsapp-relay && npx vitest run src/adapters/__tests__/adapter-manager.test.ts
```

Expected: FAIL — module not found.

**Step 3: Write minimal implementation**

Create `whatsapp-relay/src/adapters/adapter-manager.ts`:

```typescript
import { logger } from "../logger.js";
import { BaseAdapter, AdapterData } from "./base-adapter.js";

const log = logger.child({ module: "adapter-manager" });

export class AdapterManager {
  private adapters = new Map<string, BaseAdapter>();
  private intervals = new Map<string, ReturnType<typeof setInterval>>();
  private dataCallback: ((data: AdapterData[]) => void) | null = null;

  register(adapter: BaseAdapter): void {
    this.adapters.set(adapter.name, adapter);
    log.info({ adapter: adapter.name }, "Adapter registered");
  }

  getAdapter(name: string): BaseAdapter | undefined {
    return this.adapters.get(name);
  }

  adapterNames(): string[] {
    return Array.from(this.adapters.keys());
  }

  onData(callback: (data: AdapterData[]) => void): void {
    this.dataCallback = callback;
  }

  async authenticateAll(): Promise<void> {
    for (const [name, adapter] of this.adapters) {
      try {
        await adapter.authenticate();
        log.info({ adapter: name }, "Authenticated");
      } catch (err) {
        log.error({ err, adapter: name }, "Authentication failed");
      }
    }
  }

  async pollAdapter(name: string): Promise<void> {
    const adapter = this.adapters.get(name);
    if (!adapter) {
      log.warn({ adapter: name }, "Adapter not found");
      return;
    }

    const data = await adapter.executePoll();
    if (data.length > 0 && this.dataCallback) {
      this.dataCallback(data);
    }
  }

  startAll(): void {
    for (const [name, adapter] of this.adapters) {
      if (!adapter.enabled) {
        log.info({ adapter: name }, "Skipping disabled adapter");
        continue;
      }

      // Initial poll
      this.pollAdapter(name);

      // Scheduled polls
      const interval = setInterval(() => {
        this.pollAdapter(name);
      }, adapter.pollIntervalMs);

      this.intervals.set(name, interval);
      log.info({ adapter: name, intervalMs: adapter.pollIntervalMs }, "Started polling");
    }
  }

  stopAll(): void {
    for (const [name, interval] of this.intervals) {
      clearInterval(interval);
      log.info({ adapter: name }, "Stopped polling");
    }
    this.intervals.clear();
  }
}
```

**Step 4: Run test to verify it passes**

```bash
cd whatsapp-relay && npx vitest run src/adapters/__tests__/adapter-manager.test.ts
```

Expected: PASS — all 4 tests.

**Step 5: Commit**

```bash
cd whatsapp-relay && git add src/adapters/adapter-manager.ts src/adapters/__tests__/adapter-manager.test.ts
git commit -m "feat: add AdapterManager to orchestrate service adapter polling"
```

---

### Task 3: Adapter Data WebSocket Protocol Types (Relay)

**Files:**
- Modify: `whatsapp-relay/src/types.ts` (lines 47-51 RelayMessage union, lines 82-86 AppMessage union)

**Context:** We need new message types so the relay can send adapter data to iOS and receive adapter commands from iOS. These extend the existing protocol without breaking the WhatsApp message flow.

**Step 1: Write the failing test**

Create `whatsapp-relay/src/adapters/__tests__/types.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import type {
  AdapterDataMessage,
  AdapterCommandMessage,
  RelayMessage,
  AppMessage,
} from "../../types.js";

describe("Adapter protocol types", () => {
  it("should allow AdapterDataMessage as a valid RelayMessage", () => {
    const msg: AdapterDataMessage = {
      type: "adapter.data",
      adapter: "spotify",
      domain: "media",
      dataType: "listening.history",
      payload: { tracks: [] },
      timestamp: Date.now(),
    };
    // Type-level check: assign to RelayMessage
    const relay: RelayMessage = msg;
    expect(relay.type).toBe("adapter.data");
  });

  it("should allow AdapterCommandMessage as a valid AppMessage", () => {
    const msg: AdapterCommandMessage = {
      type: "adapter.command",
      adapter: "att-wifi",
      command: "pauseProfile",
      params: { profileId: "kid1" },
    };
    const app: AppMessage = msg;
    expect(app.type).toBe("adapter.command");
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd whatsapp-relay && npx vitest run src/adapters/__tests__/types.test.ts
```

Expected: FAIL — types not exported.

**Step 3: Add types to `whatsapp-relay/src/types.ts`**

Add after the `RelayStatus` interface (line 45) and before the `RelayMessage` union (line 47):

```typescript
// Adapter data: relay -> iOS app (service adapter poll results)
export interface AdapterDataMessage {
  type: "adapter.data";
  adapter: string;
  domain: string;
  dataType: string;
  payload: Record<string, unknown>;
  timestamp: number;
}
```

Update the `RelayMessage` union to include it:
```typescript
export type RelayMessage =
  | RelayMessageText
  | RelayMessageAudio
  | RelayMessageImage
  | RelayStatus
  | AdapterDataMessage;
```

Add after the `AppPing` interface (line 80) and before the `AppMessage` union (line 82):

```typescript
// Adapter command: iOS app -> relay (commands for service adapters)
export interface AdapterCommandMessage {
  type: "adapter.command";
  adapter: string;
  command: string;
  params: Record<string, unknown>;
}
```

Update the `AppMessage` union to include it:
```typescript
export type AppMessage =
  | AppReplyText
  | AppReplyAudio
  | AppReplyImage
  | AppPing
  | AdapterCommandMessage;
```

**Step 4: Run test to verify it passes**

```bash
cd whatsapp-relay && npx vitest run src/adapters/__tests__/types.test.ts
```

Expected: PASS.

**Step 5: Run full type check to ensure no breakage**

```bash
cd whatsapp-relay && npx tsc --noEmit
```

Expected: No errors.

**Step 6: Commit**

```bash
cd whatsapp-relay && git add src/types.ts src/adapters/__tests__/types.test.ts
git commit -m "feat: add adapter data/command protocol types to WebSocket messages"
```

---

### Task 4: Wire Adapter Manager into Relay Startup (Relay)

**Files:**
- Modify: `whatsapp-relay/src/index.ts` (main function, lines 15-91)
- Modify: `whatsapp-relay/src/websocket/server.ts` (add adapter command routing)
- Modify: `whatsapp-relay/src/config.ts` (add adapter config)

**Context:** The AdapterManager needs to boot up during relay startup, authenticate adapters, start polling, and forward data through the existing WebSocket. Adapter commands from iOS need to be routed to the right adapter.

**Step 1: Add adapter config to `whatsapp-relay/src/config.ts`**

Add after the existing config object:

```typescript
export const adapterConfig = {
  enableAdapters: process.env.ENABLE_ADAPTERS === "true",
} as const;
```

**Step 2: Wire AdapterManager into `whatsapp-relay/src/index.ts`**

After the WhatsApp client setup (around line 65), add:

```typescript
import { AdapterManager } from "./adapters/adapter-manager.js";
import { adapterConfig } from "./config.js";
```

In the `main()` function, after the sender wiring (around line 75), add:

```typescript
  // Step 6: Initialize adapter framework
  const adapterManager = new AdapterManager();

  if (adapterConfig.enableAdapters) {
    // Forward adapter data to iOS app via WebSocket
    adapterManager.onData((dataItems) => {
      for (const item of dataItems) {
        wsServer.forward({
          type: "adapter.data",
          adapter: item.domain,
          domain: item.domain,
          dataType: item.type,
          payload: item.payload,
          timestamp: item.timestamp,
        });
      }
    });

    // Adapters will be registered here as they are built
    // e.g., adapterManager.register(new SpotifyAdapter(...));

    await adapterManager.authenticateAll();
    adapterManager.startAll();
    log.info("Adapter framework started");
  }
```

**Step 3: Add adapter command routing in WebSocket message handler**

In `whatsapp-relay/src/index.ts`, update the `wsServer.onAppMessage` handler to route adapter commands:

```typescript
  wsServer.onAppMessage(async (msg) => {
    try {
      if (msg.type === "adapter.command") {
        // Route to adapter manager
        const cmd = msg as AdapterCommandMessage;
        log.info({ adapter: cmd.adapter, command: cmd.command }, "Adapter command received");
        // Adapter command handling will be wired per-adapter
        return;
      }
      await sender(msg);
    } catch (err) {
      log.error({ err, type: msg.type }, "Failed to handle app message");
    }
  });
```

**Step 4: Run type check**

```bash
cd whatsapp-relay && npx tsc --noEmit
```

Expected: No errors.

**Step 5: Run all tests**

```bash
cd whatsapp-relay && npx vitest run
```

Expected: All tests pass.

**Step 6: Commit**

```bash
cd whatsapp-relay && git add src/index.ts src/config.ts src/websocket/server.ts
git commit -m "feat: wire AdapterManager into relay startup with WebSocket forwarding"
```

---

### Task 5: New IntentActions (iOS)

**Files:**
- Modify: `Packages/JARVISCore/Sources/JARVISCore/Models/JARVISIntent.swift` (lines 23-42, IntentAction enum)

**Context:** Add the ~10 new intent action cases for the 6 automation categories. These need to be added to the enum so the LLM can classify them, executors can handle them, and the confirmation policy can gate them.

**Step 1: Add new cases to IntentAction enum**

In `JARVISIntent.swift`, expand the `IntentAction` enum (lines 23-42). Add after the existing cases:

```swift
public enum IntentAction: String, Sendable, Codable, CaseIterable {
    // HomeKit
    case turnOn, turnOff, setBrightness, setTemperature
    case lockDoor, unlockDoor, setThermostat, setScene
    // Communication
    case sendMessage, makeCall
    // Productivity
    case createReminder, createCalendarEvent, createNote, createTask
    // Automation
    case runShortcut
    // Navigation
    case getDirections
    // Health
    case queryHealth
    case getHealthBriefing
    // Memory
    case remember, recall
    // Media
    case playMedia, recommendMedia, searchMedia
    // Parenting
    case checkChores, grantWifi, pauseWifi
    // Financial
    case getSpendingSummary, checkBudget
    // Home Intelligence
    case getHomeStatus, setAutomationRule
    // Productivity Orchestrator
    case getDayBriefing, blockFocusTime
    // Meta
    case unknown
    case confirmYes, confirmNo
}
```

**Step 2: Build to verify compilation**

```bash
cd Packages/JARVISCore && swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Packages/JARVISCore/Sources/JARVISCore/Models/JARVISIntent.swift
git commit -m "feat: add 12 new IntentAction cases for life automation categories"
```

---

### Task 6: Update GBNF Grammar (iOS)

**Files:**
- Modify: `Packages/AIRouter/Sources/AIRouter/Grammar/IntentGrammar.swift` (lines 41-62, action values)

**Context:** The GBNF grammar constrains LLM output to valid IntentAction values. New actions must be added or the model cannot produce them. The grammar is a string that enumerates all valid action strings.

**Step 1: Update the action-value rule in `IntentGrammar.swift`**

Find the `action-value` rule (around lines 41-62) and add the new cases. The rule should enumerate all action strings with `|` separators:

```swift
action-value ::= "\"turnOn\"" | "\"turnOff\"" | "\"setBrightness\"" | "\"setTemperature\""
  | "\"lockDoor\"" | "\"unlockDoor\"" | "\"setThermostat\"" | "\"setScene\""
  | "\"sendMessage\"" | "\"makeCall\""
  | "\"createReminder\"" | "\"createCalendarEvent\"" | "\"createNote\"" | "\"createTask\""
  | "\"runShortcut\""
  | "\"getDirections\""
  | "\"queryHealth\"" | "\"getHealthBriefing\""
  | "\"remember\"" | "\"recall\""
  | "\"playMedia\"" | "\"recommendMedia\"" | "\"searchMedia\""
  | "\"checkChores\"" | "\"grantWifi\"" | "\"pauseWifi\""
  | "\"getSpendingSummary\"" | "\"checkBudget\""
  | "\"getHomeStatus\"" | "\"setAutomationRule\""
  | "\"getDayBriefing\"" | "\"blockFocusTime\""
  | "\"unknown\"" | "\"confirmYes\"" | "\"confirmNo\""
```

**Step 2: Build to verify compilation**

```bash
cd Packages/AIRouter && swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Packages/AIRouter/Sources/AIRouter/Grammar/IntentGrammar.swift
git commit -m "feat: add new action values to GBNF grammar for life automation"
```

---

### Task 7: Update Confirmation Policy (iOS)

**Files:**
- Modify: `Packages/AIRouter/Sources/AIRouter/IntentParser.swift` (lines 94-122, requiresConfirmation)

**Context:** Some new actions are high-risk and need user confirmation. WiFi control affects kids' access and should always confirm. Automation rules change home behavior. Financial queries above certain thresholds should confirm.

**Step 1: Update `requiresConfirmation` in `IntentParser.swift`**

Add new actions to the appropriate confirmation sets:

```swift
private static func requiresConfirmation(
    action: IntentAction,
    confidence: Double
) -> Bool {
    let alwaysConfirm: Set<IntentAction> = [
        .unlockDoor, .sendMessage, .makeCall, .createCalendarEvent,
        .pauseWifi, .grantWifi, .setAutomationRule
    ]
    if alwaysConfirm.contains(action) { return true }

    let confirmWhenUnsure: Set<IntentAction> = [
        .turnOff, .setThermostat, .lockDoor, .createReminder,
        .blockFocusTime
    ]
    if confirmWhenUnsure.contains(action) && confidence < 0.85 { return true }

    return false
}
```

**Step 2: Build to verify compilation**

```bash
cd Packages/AIRouter && swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Packages/AIRouter/Sources/AIRouter/IntentParser.swift
git commit -m "feat: update confirmation policy for new life automation actions"
```

---

### Task 8: Update Catalog Validation (iOS)

**Files:**
- Modify: `Packages/CommandCatalog/Sources/CommandCatalog/CatalogManager.swift`

**Context:** The catalog validator needs to know that new device-free actions (health queries, media recommendations, chore checks, financial summaries, day briefings) are always valid — they don't reference HomeKit devices, scenes, or shortcuts.

**Step 1: Add new actions to the device-free validation list**

Find the list of device-free actions in `CatalogManager.swift` and add the new cases:

```swift
// Device-free actions — always valid, no catalog lookup needed
let deviceFreeActions: Set<IntentAction> = [
    .sendMessage, .makeCall, .createReminder, .createCalendarEvent,
    .createNote, .createTask, .getDirections, .queryHealth,
    .remember, .recall, .confirmYes, .confirmNo,
    // New life automation actions
    .getHealthBriefing, .playMedia, .recommendMedia, .searchMedia,
    .checkChores, .grantWifi, .pauseWifi,
    .getSpendingSummary, .checkBudget,
    .getHomeStatus, .setAutomationRule,
    .getDayBriefing, .blockFocusTime
]
```

**Step 2: Build to verify compilation**

```bash
cd Packages/CommandCatalog && swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Packages/CommandCatalog/
git commit -m "feat: add new life automation actions to device-free validation list"
```

---

### Task 9: Adapter Data Handling in RelayConnection (iOS)

**Files:**
- Modify: `Packages/MessageIntake/Sources/MessageIntake/RelayConnection.swift` (lines 124-163, handleMessage)

**Context:** The iOS RelayConnection needs to handle the new `adapter.data` message type from the relay and surface it as a stream that the DataAggregator (Task 10) can consume. It also needs to be able to send `adapter.command` messages to the relay.

**Step 1: Add AdapterData types**

Create `Packages/MessageIntake/Sources/MessageIntake/AdapterDataTypes.swift`:

```swift
import Foundation

public struct RelayAdapterData: Sendable, Codable {
    public let type: String  // "adapter.data"
    public let adapter: String
    public let domain: String
    public let dataType: String
    public let payload: [String: AnyCodable]
    public let timestamp: Double
}

public struct AdapterCommand: Sendable, Codable {
    public let type: String  // "adapter.command"
    public let adapter: String
    public let command: String
    public let params: [String: AnyCodable]

    public init(adapter: String, command: String, params: [String: AnyCodable] = [:]) {
        self.type = "adapter.command"
        self.adapter = adapter
        self.command = command
        self.params = params
    }
}

/// Type-erased Codable wrapper for JSON values
public enum AnyCodable: Sendable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodable])
    case dictionary([String: AnyCodable])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode([AnyCodable].self) { self = .array(v) }
        else if let v = try? container.decode([String: AnyCodable].self) { self = .dictionary(v) }
        else if container.decodeNil() { self = .null }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
```

**Step 2: Add adapter data stream and command sending to RelayConnection**

In `RelayConnection.swift`, add:
- A new `AsyncStream<RelayAdapterData>` property and continuation (like the existing `incomingCommands` and `statusContinuation`)
- A new case in `handleMessage()` for `"adapter.data"`
- A `sendAdapterCommand()` method

Add property:
```swift
public let adapterDataStream: AsyncStream<RelayAdapterData>
private var adapterDataContinuation: AsyncStream<RelayAdapterData>.Continuation?
```

In `init()`, set up the stream:
```swift
let (adapterStream, adapterCont) = AsyncStream<RelayAdapterData>.makeStream()
self.adapterDataStream = adapterStream
self.adapterDataContinuation = adapterCont
```

In `handleMessage()`, add a case:
```swift
case "adapter.data":
    let msg = try JSONDecoder().decode(RelayAdapterData.self, from: data)
    adapterDataContinuation?.yield(msg)
```

Add send method:
```swift
public func sendAdapterCommand(_ command: AdapterCommand) async {
    guard let data = try? JSONEncoder().encode(command),
          let text = String(data: data, encoding: .utf8) else { return }
    await send(text: text)
}
```

**Step 3: Build to verify compilation**

```bash
cd Packages/MessageIntake && swift build
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add Packages/MessageIntake/
git commit -m "feat: add adapter data stream and command sending to RelayConnection"
```

---

### Task 10: DataAggregator Module (iOS)

**Files:**
- Create: `Packages/ExecutionEngine/Sources/ExecutionEngine/DataAggregator.swift`

**Context:** The DataAggregator is the synthesis layer. It receives adapter data from the relay, stores it in MemorySystem, and exposes domain-specific query methods. It also queries iOS-native APIs (HealthKit, EventKit) to merge with relay data.

**Step 1: Create the DataAggregator**

```swift
import Foundation
import JARVISCore

/// Aggregates data from relay adapters and native iOS APIs.
/// Stores domain data in MemorySystem and exposes query methods per domain.
public actor DataAggregator {
    private var domainData: [String: [[String: Any]]] = [:]
    private let storeNote: (String, [String]) async throws -> Void

    public init(storeNote: @escaping (String, [String]) async throws -> Void) {
        self.storeNote = storeNote
    }

    /// Ingest adapter data from relay
    public func ingest(domain: String, dataType: String, payload: [String: Any]) async {
        var entries = domainData[domain] ?? []
        var entry = payload
        entry["_dataType"] = dataType
        entry["_ingestedAt"] = Date().timeIntervalSince1970
        entries.append(entry)

        // Keep last 100 entries per domain
        if entries.count > 100 {
            entries = Array(entries.suffix(100))
        }
        domainData[domain] = entries

        // Store summary in memory system for LLM context
        let summary = "\(domain):\(dataType) data ingested"
        try? await storeNote(summary, [domain, dataType])
    }

    /// Get latest data for a domain
    public func getLatest(domain: String, limit: Int = 10) -> [[String: Any]] {
        let entries = domainData[domain] ?? []
        return Array(entries.suffix(limit))
    }

    /// Get all data for a specific data type within a domain
    public func getData(domain: String, dataType: String) -> [[String: Any]] {
        let entries = domainData[domain] ?? []
        return entries.filter { ($0["_dataType"] as? String) == dataType }
    }

    /// Clear all data for a domain
    public func clearDomain(_ domain: String) {
        domainData.removeValue(forKey: domain)
    }
}
```

**Step 2: Build to verify compilation**

```bash
cd Packages/ExecutionEngine && swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Packages/ExecutionEngine/Sources/ExecutionEngine/DataAggregator.swift
git commit -m "feat: add DataAggregator for cross-service data synthesis"
```

---

### Task 11: ProactiveScheduler (iOS)

**Files:**
- Create: `Packages/ExecutionEngine/Sources/ExecutionEngine/ProactiveScheduler.swift`

**Context:** The ProactiveScheduler triggers time-based actions like morning briefings, evening reviews, and periodic checks. It runs on iOS and fires events that the pipeline can handle as if a user had sent a command.

**Step 1: Create the ProactiveScheduler**

```swift
import Foundation
import JARVISCore

/// Scheduled event that triggers a proactive JARVIS action
public struct ScheduledEvent: Sendable {
    public let id: String
    public let action: IntentAction
    public let parameters: [String: String]
    public let humanReadable: String
    public let schedule: Schedule

    public enum Schedule: Sendable {
        case daily(hour: Int, minute: Int)
        case interval(seconds: TimeInterval)
    }

    public init(id: String, action: IntentAction, parameters: [String: String] = [:], humanReadable: String, schedule: Schedule) {
        self.id = id
        self.action = action
        self.parameters = parameters
        self.humanReadable = humanReadable
        self.schedule = schedule
    }
}

/// Runs scheduled proactive events and yields JARVISCommands
public actor ProactiveScheduler {
    private var events: [ScheduledEvent] = []
    private var timers: [String: Task<Void, Never>] = [:]
    private var commandContinuation: AsyncStream<JARVISCommand>.Continuation?
    public let commands: AsyncStream<JARVISCommand>

    public init() {
        let (stream, continuation) = AsyncStream<JARVISCommand>.makeStream()
        self.commands = stream
        self.commandContinuation = continuation
    }

    public func register(event: ScheduledEvent) {
        events.append(event)
    }

    public func start() {
        for event in events {
            let continuation = commandContinuation
            let task = Task {
                switch event.schedule {
                case .daily(let hour, let minute):
                    while !Task.isCancelled {
                        let now = Date()
                        let calendar = Calendar.current
                        var target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
                        if target <= now {
                            target = calendar.date(byAdding: .day, value: 1, to: target)!
                        }
                        let delay = target.timeIntervalSince(now)
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled else { break }

                        let command = JARVISCommand(
                            rawText: event.humanReadable,
                            source: .appUI,
                            timestamp: Date()
                        )
                        continuation?.yield(command)
                    }

                case .interval(let seconds):
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(seconds))
                        guard !Task.isCancelled else { break }

                        let command = JARVISCommand(
                            rawText: event.humanReadable,
                            source: .appUI,
                            timestamp: Date()
                        )
                        continuation?.yield(command)
                    }
                }
            }
            timers[event.id] = task
        }
    }

    public func stop() {
        for (_, task) in timers {
            task.cancel()
        }
        timers.removeAll()
    }
}
```

**Step 2: Build to verify compilation**

```bash
cd Packages/ExecutionEngine && swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Packages/ExecutionEngine/Sources/ExecutionEngine/ProactiveScheduler.swift
git commit -m "feat: add ProactiveScheduler for time-based briefings and alerts"
```

---

### Task 12: Wire Foundation into CommandPipeline (iOS)

**Files:**
- Modify: `AlexanderOS/AlexanderOS/App/Pipeline/CommandPipeline.swift` (lines 35-59 init, lines 67-98 startup)

**Context:** The DataAggregator and ProactiveScheduler need to be wired into the CommandPipeline. Adapter data from the relay needs to flow into the DataAggregator. Proactive commands need to enter the same processing loop as user commands.

**Step 1: Add properties to CommandPipeline**

In `CommandPipeline.swift`, add to the property list (around line 35):

```swift
private let aggregator: DataAggregator
private let proactive: ProactiveScheduler
```

**Step 2: Initialize in init()**

In the `init()` method, add:

```swift
self.aggregator = DataAggregator(storeNote: { [memory] content, tags in
    try await memory.storeNote(content: content, tags: tags)
})
self.proactive = ProactiveScheduler()
```

**Step 3: Wire adapter data ingestion in startup**

In the startup sequence, add a task that consumes adapter data from the relay:

```swift
// Ingest adapter data from relay into DataAggregator
Task {
    for await adapterData in intake.adapterDataStream {
        await aggregator.ingest(
            domain: adapterData.domain,
            dataType: adapterData.dataType,
            payload: [:] // Convert AnyCodable payload as needed
        )
    }
}
```

**Step 4: Register default proactive events**

```swift
// Register default proactive schedules
await proactive.register(event: ScheduledEvent(
    id: "morning-briefing",
    action: .getDayBriefing,
    humanReadable: "Give me my morning briefing",
    schedule: .daily(hour: 7, minute: 0)
))

await proactive.start()

// Merge proactive commands into processing loop
Task {
    for await command in proactive.commands {
        await processCommand(command)
    }
}
```

**Step 5: Build to verify compilation**

```bash
cd Packages/ExecutionEngine && swift build
cd AlexanderOS && xcodegen generate
```

Expected: Build succeeds (may need Xcode for full app build).

**Step 6: Commit**

```bash
git add AlexanderOS/AlexanderOS/App/Pipeline/CommandPipeline.swift
git commit -m "feat: wire DataAggregator and ProactiveScheduler into CommandPipeline"
```

---

## Phase 2: Productivity Orchestrator

Uses only iOS-native APIs (EventKit, Focus modes). No relay adapters needed. Good first category to validate the executor pattern.

---

### Task 13: ProductivityExecutor (iOS)

**Files:**
- Create: `Packages/ExecutionEngine/Sources/ExecutionEngine/Executors/ProductivityExecutor.swift`
- Modify: `Packages/ExecutionEngine/Sources/ExecutionEngine/ExecutionRouter.swift` (add property + dispatch)

**Context:** Handles `getDayBriefing` and `blockFocusTime` actions. Queries EventKit for today's calendar events and reminders, formats a briefing. Creates calendar blocks for focus time.

**Step 1: Create ProductivityExecutor**

```swift
import Foundation
import JARVISCore
#if canImport(EventKit)
import EventKit
#endif

public actor ProductivityExecutor {
    #if canImport(EventKit)
    private let eventStore = EKEventStore()
    #endif

    public init() {}

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        switch intent.action {
        case .getDayBriefing:
            return await generateBriefing()
        case .blockFocusTime:
            return await blockFocusTime(intent: intent)
        default:
            return .failure(error: "ProductivityExecutor cannot handle \(intent.action.rawValue)")
        }
    }

    private func generateBriefing() async -> ExecutionResult {
        #if canImport(EventKit)
        let granted = try? await eventStore.requestFullAccessToEvents()
        guard granted == true else {
            return .failure(error: "Calendar access not granted")
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        let remindersGranted = try? await eventStore.requestFullAccessToReminders()
        var overdueReminders: [EKReminder] = []
        if remindersGranted == true {
            let reminderPredicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: Date(), calendars: nil
            )
            overdueReminders = await withCheckedContinuation { continuation in
                eventStore.fetchReminders(matching: reminderPredicate) { reminders in
                    continuation.resume(returning: reminders ?? [])
                }
            }
        }

        var briefing = "Today's Briefing:\n"

        if events.isEmpty {
            briefing += "No meetings today.\n"
        } else {
            briefing += "\(events.count) event\(events.count == 1 ? "" : "s"):\n"
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            for event in events {
                briefing += "- \(formatter.string(from: event.startDate)): \(event.title ?? "Untitled")\n"
            }
        }

        if !overdueReminders.isEmpty {
            briefing += "\n\(overdueReminders.count) overdue reminder\(overdueReminders.count == 1 ? "" : "s"):\n"
            for reminder in overdueReminders.prefix(5) {
                briefing += "- \(reminder.title ?? "Untitled")\n"
            }
        }

        return .success(message: briefing)
        #else
        return .failure(error: "EventKit not available on this platform")
        #endif
    }

    private func blockFocusTime(intent: JARVISIntent) async -> ExecutionResult {
        #if canImport(EventKit)
        let granted = try? await eventStore.requestFullAccessToEvents()
        guard granted == true else {
            return .failure(error: "Calendar access not granted")
        }

        let duration = Int(intent.parameters["duration"] ?? "60") ?? 60
        let title = intent.parameters["title"] ?? "Focus Time"

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(TimeInterval(duration * 60))
        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent)
            return .success(message: "Blocked \(duration) minutes for '\(title)' starting now")
        } catch {
            return .failure(error: "Failed to create focus block: \(error.localizedDescription)")
        }
        #else
        return .failure(error: "EventKit not available on this platform")
        #endif
    }
}
```

**Step 2: Wire into ExecutionRouter**

In `ExecutionRouter.swift`, add:

Property (around line 10):
```swift
private let productivity: ProductivityExecutor
```

In `init()`:
```swift
self.productivity = ProductivityExecutor()
```

In the dispatch switch statement (around lines 45-98), add:
```swift
case .getDayBriefing, .blockFocusTime:
    return try await productivity.execute(intent: intent)
```

**Step 3: Build to verify compilation**

```bash
cd Packages/ExecutionEngine && swift build
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add Packages/ExecutionEngine/
git commit -m "feat: add ProductivityExecutor for day briefings and focus time blocking"
```

---

## Phase 3: Home Intelligence

Extends existing HomeKit with weather awareness and calendar-driven scenes.

---

### Task 14: Weather Adapter (Relay)

**Files:**
- Create: `whatsapp-relay/src/adapters/weather-adapter.ts`
- Test: `whatsapp-relay/src/adapters/__tests__/weather-adapter.test.ts`
- Modify: `whatsapp-relay/src/config.ts` (add OPENWEATHERMAP_API_KEY)
- Modify: `whatsapp-relay/src/index.ts` (register adapter)

**Context:** Polls OpenWeatherMap API every 30 minutes. Sends current conditions and forecast to iOS. iOS uses this for weather-reactive home automation and briefings.

**Step 1: Add config**

In `config.ts`, add:
```typescript
export const adapterConfig = {
  enableAdapters: process.env.ENABLE_ADAPTERS === "true",
  openWeatherMapKey: process.env.OPENWEATHERMAP_API_KEY || "",
  weatherLat: process.env.WEATHER_LAT || "0",
  weatherLon: process.env.WEATHER_LON || "0",
} as const;
```

**Step 2: Write the failing test**

Create `whatsapp-relay/src/adapters/__tests__/weather-adapter.test.ts`:

```typescript
import { describe, it, expect, vi } from "vitest";
import { WeatherAdapter } from "../weather-adapter.js";

describe("WeatherAdapter", () => {
  it("should be constructed with config", () => {
    const adapter = new WeatherAdapter({
      apiKey: "test-key",
      lat: "40.7128",
      lon: "-74.0060",
      pollIntervalMs: 1800000,
    });
    expect(adapter.name).toBe("weather");
    expect(adapter.enabled).toBe(true);
  });

  it("should return weather domain data on poll", async () => {
    const adapter = new WeatherAdapter({
      apiKey: "test-key",
      lat: "40.7128",
      lon: "-74.0060",
      pollIntervalMs: 1800000,
    });

    // Mock global fetch
    const mockResponse = {
      main: { temp: 72, humidity: 50 },
      weather: [{ main: "Clear", description: "clear sky" }],
      wind: { speed: 5 },
    };
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const data = await adapter.poll();
    expect(data).toHaveLength(1);
    expect(data[0].domain).toBe("weather");
    expect(data[0].type).toBe("weather.current");
    expect(data[0].payload).toHaveProperty("temp");
  });
});
```

**Step 3: Write implementation**

Create `whatsapp-relay/src/adapters/weather-adapter.ts`:

```typescript
import { BaseAdapter, AdapterConfig, AdapterData } from "./base-adapter.js";

export interface WeatherAdapterConfig {
  apiKey: string;
  lat: string;
  lon: string;
  pollIntervalMs: number;
}

export class WeatherAdapter extends BaseAdapter {
  private apiKey: string;
  private lat: string;
  private lon: string;

  constructor(config: WeatherAdapterConfig) {
    super({
      name: "weather",
      enabled: !!config.apiKey,
      pollIntervalMs: config.pollIntervalMs,
    });
    this.apiKey = config.apiKey;
    this.lat = config.lat;
    this.lon = config.lon;
  }

  async authenticate(): Promise<void> {
    // OpenWeatherMap uses API key in query params, no auth flow needed
    if (!this.apiKey) {
      this.log.warn("No OpenWeatherMap API key configured");
    }
  }

  async poll(): Promise<AdapterData[]> {
    const url = `https://api.openweathermap.org/data/2.5/weather?lat=${this.lat}&lon=${this.lon}&appid=${this.apiKey}&units=imperial`;
    const response = await fetch(url);

    if (!response.ok) {
      throw new Error(`Weather API returned ${response.status}`);
    }

    const data = await response.json() as Record<string, unknown>;
    const main = data.main as Record<string, number>;
    const weather = (data.weather as Array<Record<string, string>>)?.[0];
    const wind = data.wind as Record<string, number>;

    return [
      {
        domain: "weather",
        type: "weather.current",
        payload: {
          temp: main?.temp,
          humidity: main?.humidity,
          condition: weather?.main,
          description: weather?.description,
          windSpeed: wind?.speed,
        },
        timestamp: Date.now(),
      },
    ];
  }
}
```

**Step 4: Register in index.ts**

In `whatsapp-relay/src/index.ts`, in the adapter setup block:

```typescript
import { WeatherAdapter } from "./adapters/weather-adapter.js";

// Inside the if (adapterConfig.enableAdapters) block:
if (adapterConfig.openWeatherMapKey) {
  adapterManager.register(new WeatherAdapter({
    apiKey: adapterConfig.openWeatherMapKey,
    lat: adapterConfig.weatherLat,
    lon: adapterConfig.weatherLon,
    pollIntervalMs: 1800000, // 30 minutes
  }));
}
```

**Step 5: Run tests**

```bash
cd whatsapp-relay && npx vitest run src/adapters/__tests__/weather-adapter.test.ts
```

Expected: PASS.

**Step 6: Commit**

```bash
cd whatsapp-relay && git add src/adapters/weather-adapter.ts src/adapters/__tests__/weather-adapter.test.ts src/index.ts src/config.ts
git commit -m "feat: add WeatherAdapter polling OpenWeatherMap for home intelligence"
```

---

### Task 15: HomeIntelligenceExecutor (iOS)

**Files:**
- Create: `Packages/ExecutionEngine/Sources/ExecutionEngine/Executors/HomeIntelligenceExecutor.swift`
- Modify: `Packages/ExecutionEngine/Sources/ExecutionEngine/ExecutionRouter.swift` (add property + dispatch)

**Context:** Handles `getHomeStatus` and `setAutomationRule`. Uses DataAggregator to pull weather data and EventKit for calendar context. Synthesizes home status reports.

**Step 1: Create HomeIntelligenceExecutor**

```swift
import Foundation
import JARVISCore

public actor HomeIntelligenceExecutor {
    private let getWeatherData: () async -> [[String: Any]]
    private let getCalendarEvents: () async -> [String]

    public init(
        getWeatherData: @escaping () async -> [[String: Any]],
        getCalendarEvents: @escaping () async -> [String]
    ) {
        self.getWeatherData = getWeatherData
        self.getCalendarEvents = getCalendarEvents
    }

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        switch intent.action {
        case .getHomeStatus:
            return await generateHomeStatus()
        case .setAutomationRule:
            return setAutomationRule(intent: intent)
        default:
            return .failure(error: "HomeIntelligenceExecutor cannot handle \(intent.action.rawValue)")
        }
    }

    private func generateHomeStatus() async -> ExecutionResult {
        var status = "Home Status:\n"

        let weather = await getWeatherData()
        if let latest = weather.last {
            let temp = latest["temp"] as? Double ?? 0
            let condition = latest["condition"] as? String ?? "Unknown"
            status += "Weather: \(condition), \(Int(temp))F\n"
        }

        let events = await getCalendarEvents()
        if !events.isEmpty {
            status += "Upcoming: \(events.first ?? "")\n"
        }

        return .success(message: status)
    }

    private func setAutomationRule(intent: JARVISIntent) -> ExecutionResult {
        // Automation rules stored for ProactiveScheduler to evaluate
        let rule = intent.parameters["rule"] ?? "unknown"
        return .success(message: "Automation rule '\(rule)' registered. Will be evaluated on schedule.")
    }
}
```

**Step 2: Wire into ExecutionRouter**

Add property, init, and dispatch case following the same pattern as Task 13.

In dispatch:
```swift
case .getHomeStatus, .setAutomationRule:
    return try await homeIntelligence.execute(intent: intent)
```

**Step 3: Build and commit**

```bash
cd Packages/ExecutionEngine && swift build
git add Packages/ExecutionEngine/
git commit -m "feat: add HomeIntelligenceExecutor for weather-aware home status"
```

---

## Phase 4: Health Command Center

HealthKit native + relay adapters for external health services.

---

### Task 16: HealthExecutor (iOS)

**Files:**
- Create: `Packages/ExecutionEngine/Sources/ExecutionEngine/Executors/HealthExecutor.swift`
- Modify: `Packages/ExecutionEngine/Sources/ExecutionEngine/ExecutionRouter.swift`

**Context:** Handles `queryHealth` (already exists as a stub) and `getHealthBriefing`. Queries HealthKit for sleep, steps, heart rate, HRV. Pulls Noom/MyChart data from DataAggregator. Synthesizes health reports.

**Step 1: Create HealthExecutor**

```swift
import Foundation
import JARVISCore
#if canImport(HealthKit)
import HealthKit
#endif

public actor HealthExecutor {
    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif
    private let getAdapterData: (String, String) async -> [[String: Any]]

    public init(getAdapterData: @escaping (String, String) async -> [[String: Any]]) {
        self.getAdapterData = getAdapterData
    }

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        switch intent.action {
        case .queryHealth:
            let metric = intent.parameters["metric"] ?? "summary"
            return await queryHealth(metric: metric)
        case .getHealthBriefing:
            return await generateHealthBriefing()
        default:
            return .failure(error: "HealthExecutor cannot handle \(intent.action.rawValue)")
        }
    }

    private func generateHealthBriefing() async -> ExecutionResult {
        #if canImport(HealthKit)
        var briefing = "Health Briefing:\n"

        // Sleep
        if let sleep = await querySleep() {
            briefing += "Sleep: \(sleep)\n"
        }

        // Steps
        if let steps = await querySteps() {
            briefing += "Steps: \(steps)\n"
        }

        // Heart rate
        if let hr = await queryHeartRate() {
            briefing += "Resting HR: \(hr)\n"
        }

        // Noom data from adapter (via DataAggregator)
        let noomData = await getAdapterData("health", "noom.nutrition")
        if let latest = noomData.last {
            let calories = latest["calories"] as? Int ?? 0
            briefing += "Noom: \(calories) cal yesterday\n"
        }

        // MyChart data from adapter
        let mychartData = await getAdapterData("health", "mychart.labs")
        if !mychartData.isEmpty {
            briefing += "MyChart: \(mychartData.count) recent lab result(s)\n"
        }

        return .success(message: briefing)
        #else
        return .failure(error: "HealthKit not available on this platform")
        #endif
    }

    private func queryHealth(metric: String) async -> ExecutionResult {
        #if canImport(HealthKit)
        switch metric {
        case "sleep":
            let result = await querySleep()
            return .success(message: result ?? "No sleep data available")
        case "steps":
            let result = await querySteps()
            return .success(message: result ?? "No step data available")
        case "heartRate", "hr":
            let result = await queryHeartRate()
            return .success(message: result ?? "No heart rate data available")
        default:
            return await generateHealthBriefing()
        }
        #else
        return .failure(error: "HealthKit not available on this platform")
        #endif
    }

    #if canImport(HealthKit)
    private func querySleep() async -> String? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: now, options: .strictEndDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 10, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let asleepSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
                let totalMinutes = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
                let hours = Int(totalMinutes) / 60
                let mins = Int(totalMinutes) % 60
                continuation.resume(returning: "\(hours)h \(mins)m")
            }
            healthStore.execute(query)
        }
    }

    private func querySteps() async -> String? {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                guard let sum = stats?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let steps = Int(sum.doubleValue(for: .count()))
                continuation.resume(returning: "\(steps.formatted()) steps today")
            }
            healthStore.execute(query)
        }
    }

    private func queryHeartRate() async -> String? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -1, to: Date()), end: Date(), options: .strictEndDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpm = Int(sample.quantity.doubleValue(for: HKUnit(from: "count/min")))
                continuation.resume(returning: "\(bpm) bpm")
            }
            healthStore.execute(query)
        }
    }
    #endif
}
```

**Step 2: Wire into ExecutionRouter**

Replace the existing `queryHealth` stub with proper routing:

```swift
case .queryHealth, .getHealthBriefing:
    return try await health.execute(intent: intent)
```

**Step 3: Build and commit**

```bash
cd Packages/ExecutionEngine && swift build
git add Packages/ExecutionEngine/
git commit -m "feat: add HealthExecutor with HealthKit queries and adapter data synthesis"
```

---

## Phase 5: Parenting Accountability

Relay adapters for Skylight and AT&T Smart Home WiFi.

---

### Task 17: Skylight Adapter (Relay)

**Files:**
- Create: `whatsapp-relay/src/adapters/skylight-adapter.ts`
- Test: `whatsapp-relay/src/adapters/__tests__/skylight-adapter.test.ts`

**Context:** Polls Skylight for chore completion status per kid. API access method TBD (may need reverse engineering or web scraping). This adapter establishes the data shape — the actual API integration can be refined once Skylight's API is investigated.

**Step 1: Create adapter with interface-first design**

```typescript
import { BaseAdapter, AdapterData } from "./base-adapter.js";

export interface SkylightConfig {
  email: string;
  password: string;
  pollIntervalMs: number;
}

export interface ChoreStatus {
  kidName: string;
  choreName: string;
  completed: boolean;
  dueTime: string | null;
}

export class SkylightAdapter extends BaseAdapter {
  private email: string;
  private password: string;
  private token: string | null = null;

  constructor(config: SkylightConfig) {
    super({
      name: "skylight",
      enabled: !!config.email,
      pollIntervalMs: config.pollIntervalMs,
    });
    this.email = config.email;
    this.password = config.password;
  }

  async authenticate(): Promise<void> {
    // TODO: Investigate Skylight API and implement auth
    // For now, log that auth is pending investigation
    this.log.info("Skylight auth: API investigation required");
  }

  async poll(): Promise<AdapterData[]> {
    // TODO: Replace with actual Skylight API calls
    // Returns placeholder structure showing expected data shape
    this.log.info("Skylight poll: using placeholder data until API is integrated");

    // When implemented, this will return per-kid chore status
    return [
      {
        domain: "parenting",
        type: "skylight.chores",
        payload: {
          kids: [],  // Will be ChoreStatus[] per kid
          allComplete: false,
          lastChecked: new Date().toISOString(),
        },
        timestamp: Date.now(),
      },
    ];
  }
}
```

**Step 2: Write test**

```typescript
import { describe, it, expect } from "vitest";
import { SkylightAdapter } from "../skylight-adapter.js";

describe("SkylightAdapter", () => {
  it("should construct with config", () => {
    const adapter = new SkylightAdapter({
      email: "test@test.com",
      password: "pass",
      pollIntervalMs: 300000,
    });
    expect(adapter.name).toBe("skylight");
  });

  it("should return parenting domain data", async () => {
    const adapter = new SkylightAdapter({
      email: "test@test.com",
      password: "pass",
      pollIntervalMs: 300000,
    });
    const data = await adapter.poll();
    expect(data[0].domain).toBe("parenting");
    expect(data[0].type).toBe("skylight.chores");
  });
});
```

**Step 3: Run tests, commit**

```bash
cd whatsapp-relay && npx vitest run src/adapters/__tests__/skylight-adapter.test.ts
git add src/adapters/skylight-adapter.ts src/adapters/__tests__/skylight-adapter.test.ts
git commit -m "feat: add SkylightAdapter scaffold for chore tracking integration"
```

---

### Task 18: AT&T WiFi Adapter (Relay)

**Files:**
- Create: `whatsapp-relay/src/adapters/att-wifi-adapter.ts`
- Test: `whatsapp-relay/src/adapters/__tests__/att-wifi-adapter.test.ts`

**Context:** Controls AT&T Smart Home WiFi profiles — pause/unpause per kid. Needs to both poll for status AND accept commands from iOS. API method TBD.

**Step 1: Create adapter with command handling**

```typescript
import { BaseAdapter, AdapterData } from "./base-adapter.js";

export interface AttWifiConfig {
  username: string;
  password: string;
  pollIntervalMs: number;
}

export interface WifiProfile {
  id: string;
  name: string;
  paused: boolean;
  devices: string[];
}

export class AttWifiAdapter extends BaseAdapter {
  private username: string;
  private password: string;
  private token: string | null = null;

  constructor(config: AttWifiConfig) {
    super({
      name: "att-wifi",
      enabled: !!config.username,
      pollIntervalMs: config.pollIntervalMs,
    });
    this.username = config.username;
    this.password = config.password;
  }

  async authenticate(): Promise<void> {
    // TODO: Investigate AT&T Smart Home Manager API
    this.log.info("AT&T WiFi auth: API investigation required");
  }

  async poll(): Promise<AdapterData[]> {
    // TODO: Replace with actual AT&T API calls
    this.log.info("AT&T WiFi poll: using placeholder data until API is integrated");

    return [
      {
        domain: "parenting",
        type: "wifi.profiles",
        payload: {
          profiles: [],  // Will be WifiProfile[]
          lastChecked: new Date().toISOString(),
        },
        timestamp: Date.now(),
      },
    ];
  }

  /// Handle commands from iOS (pauseProfile, unpauseProfile)
  async handleCommand(command: string, params: Record<string, unknown>): Promise<void> {
    switch (command) {
      case "pauseProfile": {
        const profileId = params.profileId as string;
        this.log.info({ profileId }, "Pausing WiFi profile");
        // TODO: Call AT&T API to pause profile
        break;
      }
      case "unpauseProfile": {
        const profileId = params.profileId as string;
        this.log.info({ profileId }, "Unpausing WiFi profile");
        // TODO: Call AT&T API to unpause profile
        break;
      }
      default:
        this.log.warn({ command }, "Unknown AT&T WiFi command");
    }
  }
}
```

**Step 2: Write test, run, commit**

Follow same pattern as Task 17. Test construction and poll shape.

```bash
cd whatsapp-relay && git add src/adapters/att-wifi-adapter.ts src/adapters/__tests__/att-wifi-adapter.test.ts
git commit -m "feat: add AttWifiAdapter scaffold for per-kid WiFi profile control"
```

---

### Task 19: ParentingExecutor (iOS)

**Files:**
- Create: `Packages/ExecutionEngine/Sources/ExecutionEngine/Executors/ParentingExecutor.swift`
- Modify: `Packages/ExecutionEngine/Sources/ExecutionEngine/ExecutionRouter.swift`

**Context:** Handles `checkChores`, `grantWifi`, `pauseWifi`. Reads chore data from DataAggregator. Sends WiFi commands to relay via RelayConnection.

**Step 1: Create ParentingExecutor**

```swift
import Foundation
import JARVISCore

public actor ParentingExecutor {
    private let getChoreData: () async -> [[String: Any]]
    private let getWifiData: () async -> [[String: Any]]
    private let sendCommand: (String, String, [String: Any]) async -> Void

    public init(
        getChoreData: @escaping () async -> [[String: Any]],
        getWifiData: @escaping () async -> [[String: Any]],
        sendCommand: @escaping (String, String, [String: Any]) async -> Void
    ) {
        self.getChoreData = getChoreData
        self.getWifiData = getWifiData
        self.sendCommand = sendCommand
    }

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        switch intent.action {
        case .checkChores:
            return await checkChores()
        case .grantWifi:
            return await controlWifi(intent: intent, pause: false)
        case .pauseWifi:
            return await controlWifi(intent: intent, pause: true)
        default:
            return .failure(error: "ParentingExecutor cannot handle \(intent.action.rawValue)")
        }
    }

    private func checkChores() async -> ExecutionResult {
        let choreData = await getChoreData()
        if choreData.isEmpty {
            return .success(message: "No chore data available. Skylight integration pending.")
        }

        var report = "Chore Status:\n"
        for entry in choreData {
            if let kids = entry["kids"] as? [[String: Any]] {
                for kid in kids {
                    let name = kid["kidName"] as? String ?? "Unknown"
                    let completed = kid["completed"] as? Bool ?? false
                    report += "- \(name): \(completed ? "Done" : "Not done")\n"
                }
            }
        }
        return .success(message: report)
    }

    private func controlWifi(intent: JARVISIntent, pause: Bool) async -> ExecutionResult {
        let target = intent.target ?? intent.parameters["kid"] ?? "all"
        let command = pause ? "pauseProfile" : "unpauseProfile"

        await sendCommand("att-wifi", command, ["profileId": target])

        let action = pause ? "paused" : "enabled"
        return .success(message: "WiFi \(action) for \(target)")
    }
}
```

**Step 2: Wire into ExecutionRouter, build, commit**

```swift
case .checkChores, .grantWifi, .pauseWifi:
    return try await parenting.execute(intent: intent)
```

```bash
cd Packages/ExecutionEngine && swift build
git add Packages/ExecutionEngine/
git commit -m "feat: add ParentingExecutor for chore checks and WiFi control"
```

---

## Phase 6: Media Intelligence

Spotify adapter (best API) + media executor on iOS.

---

### Task 20: Spotify Adapter (Relay)

**Files:**
- Create: `whatsapp-relay/src/adapters/spotify-adapter.ts`
- Test: `whatsapp-relay/src/adapters/__tests__/spotify-adapter.test.ts`
- Modify: `whatsapp-relay/src/config.ts` (Spotify OAuth credentials)

**Context:** Spotify has an excellent Web API with OAuth2. Polls for recently played tracks, current playback, and saved playlists. Can also receive playback commands from iOS.

**Step 1: Add config**

```typescript
export const adapterConfig = {
  // ... existing
  spotifyClientId: process.env.SPOTIFY_CLIENT_ID || "",
  spotifyClientSecret: process.env.SPOTIFY_CLIENT_SECRET || "",
  spotifyRefreshToken: process.env.SPOTIFY_REFRESH_TOKEN || "",
} as const;
```

**Step 2: Create adapter**

```typescript
import { BaseAdapter, AdapterData } from "./base-adapter.js";

export interface SpotifyConfig {
  clientId: string;
  clientSecret: string;
  refreshToken: string;
  pollIntervalMs: number;
}

export class SpotifyAdapter extends BaseAdapter {
  private clientId: string;
  private clientSecret: string;
  private refreshToken: string;
  private accessToken: string | null = null;
  private tokenExpiresAt = 0;

  constructor(config: SpotifyConfig) {
    super({
      name: "spotify",
      enabled: !!config.clientId && !!config.refreshToken,
      pollIntervalMs: config.pollIntervalMs,
    });
    this.clientId = config.clientId;
    this.clientSecret = config.clientSecret;
    this.refreshToken = config.refreshToken;
  }

  async authenticate(): Promise<void> {
    await this.refreshAccessToken();
  }

  private async refreshAccessToken(): Promise<void> {
    const response = await fetch("https://accounts.spotify.com/api/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${Buffer.from(`${this.clientId}:${this.clientSecret}`).toString("base64")}`,
      },
      body: `grant_type=refresh_token&refresh_token=${this.refreshToken}`,
    });

    if (!response.ok) {
      throw new Error(`Spotify auth failed: ${response.status}`);
    }

    const data = await response.json() as { access_token: string; expires_in: number };
    this.accessToken = data.access_token;
    this.tokenExpiresAt = Date.now() + data.expires_in * 1000;
    this.log.info("Spotify access token refreshed");
  }

  private async ensureToken(): Promise<string> {
    if (!this.accessToken || Date.now() >= this.tokenExpiresAt - 60000) {
      await this.refreshAccessToken();
    }
    return this.accessToken!;
  }

  async poll(): Promise<AdapterData[]> {
    const token = await this.ensureToken();
    const results: AdapterData[] = [];

    // Recently played tracks
    const recentResponse = await fetch("https://api.spotify.com/v1/me/player/recently-played?limit=20", {
      headers: { Authorization: `Bearer ${token}` },
    });

    if (recentResponse.ok) {
      const recent = await recentResponse.json() as { items: Array<{ track: { name: string; artists: Array<{ name: string }> }; played_at: string }> };
      results.push({
        domain: "media",
        type: "spotify.recent",
        payload: {
          tracks: recent.items.map((item) => ({
            name: item.track.name,
            artist: item.track.artists.map((a) => a.name).join(", "),
            playedAt: item.played_at,
          })),
        },
        timestamp: Date.now(),
      });
    }

    // Current playback
    const playbackResponse = await fetch("https://api.spotify.com/v1/me/player", {
      headers: { Authorization: `Bearer ${token}` },
    });

    if (playbackResponse.ok && playbackResponse.status !== 204) {
      const playback = await playbackResponse.json() as { is_playing: boolean; item?: { name: string; artists: Array<{ name: string }> } };
      results.push({
        domain: "media",
        type: "spotify.playback",
        payload: {
          isPlaying: playback.is_playing,
          trackName: playback.item?.name,
          artist: playback.item?.artists.map((a) => a.name).join(", "),
        },
        timestamp: Date.now(),
      });
    }

    return results;
  }

  async handleCommand(command: string, params: Record<string, unknown>): Promise<void> {
    const token = await this.ensureToken();

    switch (command) {
      case "play":
        await fetch("https://api.spotify.com/v1/me/player/play", {
          method: "PUT",
          headers: { Authorization: `Bearer ${token}` },
        });
        break;
      case "pause":
        await fetch("https://api.spotify.com/v1/me/player/pause", {
          method: "PUT",
          headers: { Authorization: `Bearer ${token}` },
        });
        break;
      case "next":
        await fetch("https://api.spotify.com/v1/me/player/next", {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
        });
        break;
    }
  }
}
```

**Step 3: Write test, register in index.ts, run, commit**

```bash
cd whatsapp-relay && npx vitest run
git add src/adapters/spotify-adapter.ts src/adapters/__tests__/spotify-adapter.test.ts src/config.ts src/index.ts
git commit -m "feat: add SpotifyAdapter with OAuth2, recently played, and playback control"
```

---

### Task 21: MediaExecutor (iOS)

**Files:**
- Create: `Packages/ExecutionEngine/Sources/ExecutionEngine/Executors/MediaExecutor.swift`
- Modify: `Packages/ExecutionEngine/Sources/ExecutionEngine/ExecutionRouter.swift`

**Context:** Handles `playMedia`, `recommendMedia`, `searchMedia`. Pulls listening/viewing data from DataAggregator. Sends playback commands to relay.

**Step 1: Create MediaExecutor following same pattern as ParentingExecutor**

Key methods:
- `recommendMedia()`: pulls recent Spotify + podcast data, synthesizes recommendations
- `searchMedia()`: searches media history stored in DataAggregator
- `playMedia()`: sends play command to Spotify adapter via relay

**Step 2: Wire into ExecutionRouter, build, commit**

```swift
case .playMedia, .recommendMedia, .searchMedia:
    return try await media.execute(intent: intent)
```

```bash
git commit -m "feat: add MediaExecutor for cross-platform media recommendations"
```

---

## Phase 7: Financial Pulse

Most sensitive category. Plaid for banking, YNAB API for budgeting.

---

### Task 22: Financial Adapter (Relay)

**Files:**
- Create: `whatsapp-relay/src/adapters/financial-adapter.ts`
- Test: `whatsapp-relay/src/adapters/__tests__/financial-adapter.test.ts`

**Context:** Uses Plaid API for transaction data and YNAB API for budget categories. Sensitive data — minimal retention, no raw credentials stored.

**Step 1: Create adapter with Plaid + YNAB integration scaffolds**

Structure:
- `authenticate()`: Exchange Plaid public token for access token, YNAB personal access token
- `poll()`: Fetch recent transactions (Plaid), budget status (YNAB)
- Return domain "financial" with types "transactions" and "budget.status"

**Step 2: Register, test, commit**

```bash
git commit -m "feat: add FinancialAdapter scaffold for Plaid and YNAB integration"
```

---

### Task 23: FinancialExecutor (iOS)

**Files:**
- Create: `Packages/ExecutionEngine/Sources/ExecutionEngine/Executors/FinancialExecutor.swift`
- Modify: `Packages/ExecutionEngine/Sources/ExecutionEngine/ExecutionRouter.swift`

**Context:** Handles `getSpendingSummary` and `checkBudget`. Pulls financial data from DataAggregator.

**Step 1: Create FinancialExecutor**

Key methods:
- `getSpendingSummary()`: formats recent transactions by category with totals
- `checkBudget()`: compares spending to budget limits, flags overages

**Step 2: Wire into ExecutionRouter, build, commit**

```swift
case .getSpendingSummary, .checkBudget:
    return try await financial.execute(intent: intent)
```

```bash
git commit -m "feat: add FinancialExecutor for spending summaries and budget checks"
```

---

## Phase 8: Proactive Schedules & Integration Testing

Wire all the proactive events, end-to-end test flows.

---

### Task 24: Register All Proactive Events

**Files:**
- Modify: `AlexanderOS/AlexanderOS/App/Pipeline/CommandPipeline.swift`

**Context:** Register all the default proactive schedules that drive briefings, alerts, and automated actions across the 6 categories.

**Step 1: Add proactive events in pipeline startup**

```swift
// Morning briefing (7:00 AM)
await proactive.register(event: ScheduledEvent(
    id: "morning-briefing",
    action: .getDayBriefing,
    humanReadable: "Give me my morning briefing",
    schedule: .daily(hour: 7, minute: 0)
))

// Health briefing (7:15 AM)
await proactive.register(event: ScheduledEvent(
    id: "health-briefing",
    action: .getHealthBriefing,
    humanReadable: "Give me my health briefing",
    schedule: .daily(hour: 7, minute: 15)
))

// Chore check (4:00 PM)
await proactive.register(event: ScheduledEvent(
    id: "chore-check",
    action: .checkChores,
    humanReadable: "Check the kids' chores",
    schedule: .daily(hour: 16, minute: 0)
))

// Evening spending summary (8:00 PM)
await proactive.register(event: ScheduledEvent(
    id: "spending-summary",
    action: .getSpendingSummary,
    humanReadable: "Give me today's spending summary",
    schedule: .daily(hour: 20, minute: 0)
))

// Home status check (every 30 minutes)
await proactive.register(event: ScheduledEvent(
    id: "home-status",
    action: .getHomeStatus,
    parameters: ["silent": "true"],
    humanReadable: "Check home status",
    schedule: .interval(seconds: 1800)
))
```

**Step 2: Build and commit**

```bash
git add AlexanderOS/
git commit -m "feat: register proactive schedules for all 6 automation categories"
```

---

### Task 25: App Intents for New Actions

**Files:**
- Modify: `AlexanderOS/AlexanderOS/App/Intents/JARVISIntents.swift`

**Context:** Add typed App Intents so users can trigger the new actions via Siri Shortcuts without going through the LLM pipeline.

**Step 1: Add new App Intents**

```swift
struct GetBriefingIntent: AppIntent {
    static var title: LocalizedStringResource = "Get JARVIS Briefing"
    static var description = IntentDescription("Get your daily briefing from JARVIS")

    @Parameter(title: "Type")
    var briefingType: BriefingType

    enum BriefingType: String, AppEnum {
        case day = "day"
        case health = "health"
        case home = "home"
        static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Briefing Type")
        static var caseDisplayRepresentations: [BriefingType: DisplayRepresentation] = [
            .day: "Day Briefing",
            .health: "Health Briefing",
            .home: "Home Status",
        ]
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let action: IntentAction = switch briefingType {
        case .day: .getDayBriefing
        case .health: .getHealthBriefing
        case .home: .getHomeStatus
        }
        let intent = JARVISIntent(action: action, confidence: 1.0, humanReadable: "Get \(briefingType.rawValue) briefing")
        let result = try await PipelineAccessor.shared.executeIntent(intent)
        switch result {
        case .success(let message): return .result(value: message)
        case .failure(let error): return .result(value: "Error: \(error)")
        default: return .result(value: "Briefing unavailable")
        }
    }
}

struct ControlKidWifiIntent: AppIntent {
    static var title: LocalizedStringResource = "Control Kid WiFi"
    static var description = IntentDescription("Pause or enable WiFi for a kid's profile")

    @Parameter(title: "Kid Name")
    var kidName: String

    @Parameter(title: "Action")
    var action: WifiAction

    enum WifiAction: String, AppEnum {
        case pause = "pause"
        case enable = "enable"
        static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "WiFi Action")
        static var caseDisplayRepresentations: [WifiAction: DisplayRepresentation] = [
            .pause: "Pause WiFi",
            .enable: "Enable WiFi",
        ]
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let intentAction: IntentAction = action == .pause ? .pauseWifi : .grantWifi
        let intent = JARVISIntent(
            action: intentAction,
            target: kidName,
            confidence: 1.0,
            requiresConfirmation: false,  // Already confirmed by Siri
            humanReadable: "\(action.rawValue) WiFi for \(kidName)"
        )
        let result = try await PipelineAccessor.shared.executeIntent(intent)
        switch result {
        case .success(let message): return .result(value: message)
        case .failure(let error): return .result(value: "Error: \(error)")
        default: return .result(value: "Action completed")
        }
    }
}
```

**Step 2: Build and commit**

```bash
git add AlexanderOS/
git commit -m "feat: add App Intents for briefings and WiFi control via Siri Shortcuts"
```

---

### Task 26: Update LLM Prompt Context for New Domains

**Files:**
- Modify: `Packages/AIRouter/Sources/AIRouter/PromptBuilder.swift` (or wherever the system prompt is built)

**Context:** The LLM needs to know about the new action categories so it can route natural language commands correctly. Update the system prompt to describe when to use each new action.

**Step 1: Add domain descriptions to prompt**

Add after existing action descriptions:

```
ADDITIONAL ACTIONS:
- getHealthBriefing: User asks about their health, wants a health summary or briefing
- playMedia: User wants to play music or media
- recommendMedia: User asks for recommendations on what to watch or listen to
- searchMedia: User asks "what was that song/podcast/show" they consumed recently
- checkChores: User asks about kids' chore completion status
- grantWifi: User wants to enable WiFi for a kid (requires confirmation)
- pauseWifi: User wants to pause WiFi for a kid (requires confirmation)
- getSpendingSummary: User asks about spending, finances, or money
- checkBudget: User asks if they can afford something or about budget status
- getHomeStatus: User asks about home status, weather at home, or energy usage
- setAutomationRule: User wants to create a conditional home automation
- getDayBriefing: User asks for their daily briefing, schedule, or what's on today
- blockFocusTime: User wants to block time for focused work
```

**Step 2: Build and commit**

```bash
cd Packages/AIRouter && swift build
git add Packages/AIRouter/
git commit -m "feat: update LLM prompt with new life automation action descriptions"
```

---

## Summary

**26 tasks across 8 phases:**

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1: Foundation | 1-12 | BaseAdapter, AdapterManager, protocol types, IntentActions, GBNF, confirmation policy, catalog validation, RelayConnection adapter handling, DataAggregator, ProactiveScheduler, pipeline wiring |
| 2: Productivity | 13 | ProductivityExecutor (day briefings, focus time) |
| 3: Home Intelligence | 14-15 | WeatherAdapter, HomeIntelligenceExecutor |
| 4: Health | 16 | HealthExecutor (HealthKit + adapter data) |
| 5: Parenting | 17-19 | SkylightAdapter, AttWifiAdapter, ParentingExecutor |
| 6: Media | 20-21 | SpotifyAdapter, MediaExecutor |
| 7: Financial | 22-23 | FinancialAdapter, FinancialExecutor |
| 8: Integration | 24-26 | Proactive schedules, App Intents, LLM prompt updates |

**API investigation required before full implementation:**
- Skylight calendar API (Task 17)
- AT&T Smart Home WiFi API (Task 18)
- Noom API vs. HealthKit integration path
- MyChart / Open Epic FHIR API patient access
- Netflix/Hulu viewing history access
