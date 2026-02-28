import http from "http";
import { config } from "./config.js";
import { logger } from "./logger.js";
import { createWhatsAppClient } from "./whatsapp/client.js";
import { createMessageHandler } from "./whatsapp/handlers.js";
import { createSender } from "./whatsapp/sender.js";
import { createWebSocketServer } from "./websocket/server.js";
import type { WhatsAppConnectionState } from "./types.js";

const log = logger.child({ module: "main" });
const startTime = Date.now();

let waState: WhatsAppConnectionState = "disconnected";

async function main() {
  log.info("Alexander OS WhatsApp Relay starting...");

  // 1. Start WebSocket server for iOS app
  const wsServer = createWebSocketServer();
  wsServer.start();

  // 2. Start health check HTTP server
  const httpServer = http.createServer((req, res) => {
    if (req.url === "/health") {
      const uptime = Math.floor((Date.now() - startTime) / 1000);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          status: "ok",
          whatsapp: waState,
          iosConnected: wsServer.getClientCount() > 0,
          uptime,
        }),
      );
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  httpServer.listen(config.httpPort, () => {
    log.info({ port: config.httpPort }, "Health check server listening");
  });

  // 3. Connect to WhatsApp
  const sock = await createWhatsAppClient(
    (state) => {
      waState = state;
      const uptime = Math.floor((Date.now() - startTime) / 1000);
      wsServer.broadcastStatus(state, uptime);
      log.info({ waState: state }, "WhatsApp connection state changed");
    },
    // Initial handler - will be replaced once we have the message handler
    () => {},
  );

  // 4. Wire up message handling: WA -> iOS app
  const messageHandler = createMessageHandler(sock, (msg) => {
    wsServer.forward(msg);
  });

  // Re-register with proper handler
  sock.ev.on("messages.upsert", (upsert) => {
    messageHandler({ "messages.upsert": upsert });
  });

  // 5. Wire up reply handling: iOS app -> WA
  const sender = createSender(sock);
  wsServer.onAppMessage(async (msg) => {
    try {
      await sender(msg);
    } catch (err) {
      log.error({ err, type: msg.type }, "Failed to send reply");
    }
  });

  // 6. Periodic status broadcast
  setInterval(() => {
    const uptime = Math.floor((Date.now() - startTime) / 1000);
    wsServer.broadcastStatus(waState, uptime);
  }, 30_000);

  log.info(
    {
      wsPort: config.wsPort,
      httpPort: config.httpPort,
      targetJid: config.targetJid || "(all)",
    },
    "Relay fully initialized",
  );
}

main().catch((err) => {
  log.fatal({ err }, "Fatal error");
  process.exit(1);
});

// Graceful shutdown
process.on("SIGINT", () => {
  log.info("Shutting down...");
  process.exit(0);
});

process.on("SIGTERM", () => {
  log.info("Shutting down...");
  process.exit(0);
});
