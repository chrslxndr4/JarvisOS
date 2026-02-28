# JarvisOS (Alexander OS)

A local-first AI assistant iOS app that receives voice and text commands from Meta Ray-Ban glasses via WhatsApp, processes them with on-device AI, and executes real-world actions.

```
Ray-Ban Glasses -> WhatsApp -> Mac Relay (Node.js/Baileys)
                                    |
                                    | WebSocket (JSON)
                                    v
                          iOS App (Alexander OS)
                          ┌─────────────────────┐
                          │ 1. Message Intake    │  <- WebSocket + whisper.cpp
                          │ 2. AI Router         │  <- llama.cpp + GBNF grammar
                          │ 3. Command Catalog   │  <- HomeKit discovery
                          │ 4. Execution Engine  │  <- HomeKit, Shortcuts, EventKit
                          │ 5. Memory System     │  <- SQLite/GRDB + FTS5
                          │ 6. Reply Handler     │  <- Format + send via WebSocket
                          └─────────────────────┘
                                    |
                                    v
                          Mac Relay -> WhatsApp -> Ray-Bans
```

## How It Works

1. You speak a command through your Ray-Ban glasses ("turn off the living room lights")
2. WhatsApp sends the voice note to the relay running on your Mac
3. The relay forwards the audio to the iOS app over WebSocket
4. whisper.cpp transcribes the audio on-device
5. Qwen 2.5 1.5B classifies the intent using GBNF grammar constraints (zero hallucinated actions)
6. The execution engine controls your HomeKit devices, creates reminders, runs shortcuts, etc.
7. A text reply is sent back through WhatsApp to your glasses

Everything runs locally. No cloud AI required.

## Project Structure

```
├── whatsapp-relay/          # Node.js relay (Baileys + WebSocket)
│   └── src/
│       ├── whatsapp/        # Baileys client, message handlers, sender
│       ├── websocket/       # WebSocket server for iOS app
│       └── types.ts         # Shared protocol types
│
├── AlexanderOS/             # iOS app (SwiftUI)
│   ├── AlexanderOS/
│   │   ├── App/             # Entry point, environment, pipeline, App Intents
│   │   ├── UI/              # Dashboard, Command Log, Settings
│   │   └── Configuration/   # App config
│   ├── Scripts/             # Model download + XCFramework build scripts
│   └── project.yml          # xcodegen spec
│
└── Packages/                # Local SPM packages
    ├── JARVISCore/          # Shared models, protocols, model download manager
    ├── MessageIntake/       # WebSocket client + whisper.cpp transcription
    ├── AIRouter/            # llama.cpp engine, GBNF grammar, prompt builder
    ├── CommandCatalog/      # HomeKit discovery + shortcut registry
    ├── ExecutionEngine/     # HomeKit, Shortcuts, Reminders, Calendar, Navigation
    ├── MemorySystem/        # GRDB/SQLite with FTS5 full-text search
    └── ReplyHandler/        # Response formatting + relay transport
```

## Supported Actions

| Category | Actions |
|----------|---------|
| HomeKit | Turn on/off, set brightness, set temperature, lock/unlock, activate scenes |
| Productivity | Create reminders, calendar events, notes, tasks |
| Automation | Run Siri Shortcuts by name |
| Navigation | Get directions (opens Maps) |
| Communication | Send messages, make calls |
| Memory | Remember/recall information (FTS5 search) |

High-risk actions (unlock door, send message, make call) require confirmation before execution.

## Setup

### Prerequisites

- Mac with Node.js 18+
- iPhone running iOS 17+ (ideally iPhone 15 Pro / 16 Pro for best AI performance)
- Xcode 16+
- WhatsApp account
- Meta Ray-Ban glasses (or any WhatsApp-connected device)

### 1. WhatsApp Relay

```bash
cd whatsapp-relay
cp .env.example .env
# Edit .env with your settings (TARGET_JID, ports, etc.)
npm install
npm run dev
# Scan the QR code with WhatsApp
```

### 2. AI Models

Download the models (~1.2 GB total):

```bash
./AlexanderOS/Scripts/download-models.sh
```

Or download them in-app on first launch.

### 3. Build XCFrameworks

Build llama.cpp and whisper.cpp for iOS:

```bash
./AlexanderOS/Scripts/build-xcframeworks.sh
```

### 4. iOS App

```bash
# Ensure Xcode is selected
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Regenerate project (if needed)
cd AlexanderOS
brew install xcodegen  # if not installed
xcodegen generate

# Open in Xcode
open AlexanderOS.xcodeproj
```

- Set your development team and bundle ID
- Enable the `LLAMA_CPP_AVAILABLE` and `WHISPER_CPP_AVAILABLE` Swift flags in Build Settings
- Build and run on your device

### 5. Connect

- Open the app and go to Settings
- Enter your Mac's local IP as the relay URL (e.g., `ws://192.168.1.100:8080`)
- The dashboard should show green status indicators for Relay and WhatsApp

## AI Architecture

- **LLM**: Qwen 2.5 1.5B Instruct (Q4_K_M quantization, ~1 GB) — runs at 400+ tokens/sec on A18 Pro
- **Speech**: whisper-base.en (~148 MB) — sub-1s transcription for voice commands
- **Constraint**: GBNF grammar forces the LLM to output valid JSON matching the intent schema. The grammar enumerates all 22 possible actions — the model literally cannot hallucinate an action that doesn't exist.
- **Prompt**: ChatML format with live HomeKit device catalog injected into the system prompt. The LLM only sees devices that actually exist in your home.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| iOS App | SwiftUI, Swift Concurrency (actors) |
| LLM Inference | llama.cpp (Metal GPU acceleration) |
| Speech-to-Text | whisper.cpp (Metal GPU acceleration) |
| Database | GRDB.swift 7.0 (SQLite + FTS5) |
| Smart Home | HomeKit (HMHomeManager) |
| WhatsApp | Baileys v6 (unofficial WhatsApp Web API) |
| WebSocket | URLSessionWebSocketTask (iOS) / ws (Node.js) |
| Project Gen | xcodegen |

## License

MIT
