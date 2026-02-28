import { WASocket, proto, downloadMediaMessage, BaileysEventMap } from "@whiskeysockets/baileys";
import { config } from "../config.js";
import { logger } from "../logger.js";
import type { RelayMessage } from "../types.js";

const log = logger.child({ module: "whatsapp-handlers" });

export function createMessageHandler(
  sock: WASocket,
  forward: (msg: RelayMessage) => void,
) {
  return async (events: Partial<BaileysEventMap>) => {
    const upsert = events["messages.upsert"];
    if (!upsert || upsert.type !== "notify") return;

    for (const msg of upsert.messages) {
      if (msg.key.fromMe) continue;
      if (!msg.message) continue;

      const from = msg.key.remoteJid || "";
      const pushName = msg.pushName || "Unknown";
      const id = msg.key.id || "";
      const timestamp = typeof msg.messageTimestamp === "number"
        ? msg.messageTimestamp
        : Date.now() / 1000;

      // Filter to target JID if configured
      if (config.targetJid && from !== config.targetJid) {
        log.debug({ from, targetJid: config.targetJid }, "Ignoring message from non-target JID");
        continue;
      }

      try {
        await processMessage(sock, msg, { id, from, pushName, timestamp }, forward);
      } catch (err) {
        log.error({ err, id }, "Failed to process message");
      }
    }
  };
}

async function processMessage(
  sock: WASocket,
  msg: proto.IWebMessageInfo,
  meta: { id: string; from: string; pushName: string; timestamp: number },
  forward: (msg: RelayMessage) => void,
) {
  const message = msg.message!;

  // Text message
  const textBody =
    message.conversation ||
    message.extendedTextMessage?.text;

  if (textBody) {
    log.info({ from: meta.from, body: textBody.slice(0, 50) }, "Text message received");
    forward({
      type: "whatsapp.message.text",
      id: meta.id,
      from: meta.from,
      pushName: meta.pushName,
      body: textBody,
      timestamp: meta.timestamp,
    });
    return;
  }

  // Audio message (voice note)
  const audioMessage = message.audioMessage;
  if (audioMessage) {
    log.info(
      { from: meta.from, seconds: audioMessage.seconds, ptt: audioMessage.ptt },
      "Audio message received",
    );

    const buffer = await downloadMediaMessage(msg, "buffer", {}) as Buffer;
    const base64 = buffer.toString("base64");

    forward({
      type: "whatsapp.message.audio",
      id: meta.id,
      from: meta.from,
      pushName: meta.pushName,
      mimetype: audioMessage.mimetype || "audio/ogg; codecs=opus",
      seconds: audioMessage.seconds || 0,
      data: base64,
      ptt: audioMessage.ptt || false,
      timestamp: meta.timestamp,
    });
    return;
  }

  // Image message
  const imageMessage = message.imageMessage;
  if (imageMessage) {
    log.info(
      { from: meta.from, caption: imageMessage.caption?.slice(0, 50) },
      "Image message received",
    );

    const buffer = await downloadMediaMessage(msg, "buffer", {}) as Buffer;
    const base64 = buffer.toString("base64");

    forward({
      type: "whatsapp.message.image",
      id: meta.id,
      from: meta.from,
      pushName: meta.pushName,
      mimetype: imageMessage.mimetype || "image/jpeg",
      caption: imageMessage.caption || null,
      width: imageMessage.width || 0,
      height: imageMessage.height || 0,
      data: base64,
      timestamp: meta.timestamp,
    });
    return;
  }

  log.debug({ from: meta.from, messageTypes: Object.keys(message) }, "Unsupported message type");
}
