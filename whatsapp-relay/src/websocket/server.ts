import { WebSocketServer, WebSocket } from "ws";
import { IncomingMessage } from "http";
import { config } from "../config.js";
import { logger } from "../logger.js";
import type { RelayMessage, AppMessage, WhatsAppConnectionState } from "../types.js";

const log = logger.child({ module: "ws-server" });

export interface RelayWebSocketServer {
  start(): void;
  forward(msg: RelayMessage): void;
  onAppMessage(handler: (msg: AppMessage) => void): void;
  broadcastStatus(waState: WhatsAppConnectionState, uptime: number): void;
  getClientCount(): number;
}

export function createWebSocketServer(): RelayWebSocketServer {
  let wss: WebSocketServer;
  let client: WebSocket | null = null;
  let appMessageHandler: ((msg: AppMessage) => void) | null = null;

  function isAllowed(req: IncomingMessage): boolean {
    if (config.allowedIp === "*") return true;
    const ip = req.socket.remoteAddress || "";
    // Normalize IPv6-mapped IPv4
    const normalized = ip.replace(/^::ffff:/, "");
    return normalized === config.allowedIp || ip === config.allowedIp;
  }

  function start() {
    wss = new WebSocketServer({ port: config.wsPort });

    wss.on("listening", () => {
      log.info({ port: config.wsPort }, "WebSocket server listening");
    });

    wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
      const ip = req.socket.remoteAddress || "unknown";

      if (!isAllowed(req)) {
        log.warn({ ip }, "Rejected connection from unauthorized IP");
        ws.close(4003, "Forbidden");
        return;
      }

      // Single-client model: disconnect existing client
      if (client && client.readyState === WebSocket.OPEN) {
        log.info("Disconnecting previous client for new connection");
        client.close(4001, "Replaced by new connection");
      }

      client = ws;
      log.info({ ip }, "iOS app connected");

      ws.on("message", (data: Buffer) => {
        try {
          const msg = JSON.parse(data.toString()) as AppMessage;
          log.debug({ type: msg.type }, "Received app message");

          if (msg.type === "ping") {
            ws.send(JSON.stringify({ type: "pong" }));
            return;
          }

          if (appMessageHandler) {
            appMessageHandler(msg);
          }
        } catch (err) {
          log.error({ err }, "Failed to parse app message");
        }
      });

      ws.on("close", (code: number, reason: Buffer) => {
        log.info({ code, reason: reason.toString() }, "iOS app disconnected");
        if (client === ws) {
          client = null;
        }
      });

      ws.on("error", (err: Error) => {
        log.error({ err }, "WebSocket client error");
      });
    });

    wss.on("error", (err: Error) => {
      log.error({ err }, "WebSocket server error");
    });
  }

  function forward(msg: RelayMessage) {
    if (!client || client.readyState !== WebSocket.OPEN) {
      log.debug({ type: msg.type }, "No iOS client connected, dropping message");
      return;
    }

    try {
      client.send(JSON.stringify(msg));
      log.debug({ type: msg.type }, "Forwarded to iOS app");
    } catch (err) {
      log.error({ err }, "Failed to forward message");
    }
  }

  function onAppMessage(handler: (msg: AppMessage) => void) {
    appMessageHandler = handler;
  }

  function broadcastStatus(waState: WhatsAppConnectionState, uptime: number) {
    forward({
      type: "relay.status",
      whatsapp: waState,
      uptime,
    });
  }

  function getClientCount(): number {
    return client && client.readyState === WebSocket.OPEN ? 1 : 0;
  }

  return { start, forward, onAppMessage, broadcastStatus, getClientCount };
}
