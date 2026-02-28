import makeWASocket, {
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
  WASocket,
  BaileysEventMap,
} from "@whiskeysockets/baileys";
import { Boom } from "@hapi/boom";
import { config } from "../config.js";
import { logger } from "../logger.js";

const log = logger.child({ module: "whatsapp-client" });

export type ConnectionStateListener = (state: "connected" | "connecting" | "disconnected") => void;
export type MessageListener = (events: Partial<BaileysEventMap>) => void;

export async function createWhatsAppClient(
  onConnectionState: ConnectionStateListener,
  onMessage: MessageListener,
): Promise<WASocket> {
  const { state, saveCreds } = await useMultiFileAuthState(config.authDir);
  const { version } = await fetchLatestBaileysVersion();

  log.info({ version }, "Using WA Web version");

  const sock = makeWASocket({
    version,
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, logger.child({ module: "signal-keys" })),
    },
    logger: logger.child({ module: "baileys" }),
    printQRInTerminal: true,
    generateHighQualityLinkPreview: false,
    syncFullHistory: false,
  });

  sock.ev.on("creds.update", saveCreds);

  sock.ev.on("connection.update", (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      log.info("QR code printed to terminal - scan with WhatsApp");
    }

    if (connection === "close") {
      const statusCode = (lastDisconnect?.error as Boom)?.output?.statusCode;
      const shouldReconnect = statusCode !== DisconnectReason.loggedOut;

      log.warn({ statusCode, shouldReconnect }, "Connection closed");
      onConnectionState("disconnected");

      if (shouldReconnect) {
        log.info("Reconnecting in 3 seconds...");
        setTimeout(() => {
          createWhatsAppClient(onConnectionState, onMessage);
        }, 3000);
      } else {
        log.error("Logged out - delete .auth folder and restart to re-authenticate");
      }
    } else if (connection === "open") {
      log.info("WhatsApp connection established");
      onConnectionState("connected");
    } else if (connection === "connecting") {
      onConnectionState("connecting");
    }
  });

  sock.ev.on("messages.upsert", (upsert) => {
    onMessage({ "messages.upsert": upsert });
  });

  return sock;
}
