// ============================================================
// WebSocket Protocol Types - THE CONTRACT between relay and iOS
// ============================================================

// --- Relay -> iOS App ---

export interface RelayMessageText {
  type: "whatsapp.message.text";
  id: string;
  from: string;
  pushName: string;
  body: string;
  timestamp: number;
}

export interface RelayMessageAudio {
  type: "whatsapp.message.audio";
  id: string;
  from: string;
  pushName: string;
  mimetype: string;
  seconds: number;
  data: string; // base64
  ptt: boolean; // push-to-talk (voice note)
  timestamp: number;
}

export interface RelayMessageImage {
  type: "whatsapp.message.image";
  id: string;
  from: string;
  pushName: string;
  mimetype: string;
  caption: string | null;
  width: number;
  height: number;
  data: string; // base64
  timestamp: number;
}

export interface RelayStatus {
  type: "relay.status";
  whatsapp: "connected" | "connecting" | "disconnected";
  uptime: number; // seconds since relay started
}

export type RelayMessage =
  | RelayMessageText
  | RelayMessageAudio
  | RelayMessageImage
  | RelayStatus;

// --- iOS App -> Relay ---

export interface AppReplyText {
  type: "reply.text";
  to: string; // JID
  body: string;
  quotedId?: string;
}

export interface AppReplyAudio {
  type: "reply.audio";
  to: string;
  data: string; // base64
  mimetype: string;
  ptt: boolean;
}

export interface AppReplyImage {
  type: "reply.image";
  to: string;
  data: string; // base64
  mimetype: string;
  caption?: string;
}

export interface AppPing {
  type: "ping";
}

export type AppMessage =
  | AppReplyText
  | AppReplyAudio
  | AppReplyImage
  | AppPing;

// --- Internal ---

export type WhatsAppConnectionState = "connected" | "connecting" | "disconnected";
