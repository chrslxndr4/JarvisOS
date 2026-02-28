import { WASocket, AnyMessageContent } from "@whiskeysockets/baileys";
import { logger } from "../logger.js";
import type { AppMessage } from "../types.js";

const log = logger.child({ module: "whatsapp-sender" });

export function createSender(sock: WASocket) {
  return async (msg: AppMessage) => {
    switch (msg.type) {
      case "reply.text": {
        const content: AnyMessageContent = { text: msg.body };
        if (msg.quotedId) {
          (content as any).quoted = { key: { id: msg.quotedId, remoteJid: msg.to } };
        }
        log.info({ to: msg.to, body: msg.body.slice(0, 50) }, "Sending text reply");
        await sock.sendMessage(msg.to, content);
        break;
      }

      case "reply.audio": {
        const audioBuffer = Buffer.from(msg.data, "base64");
        log.info({ to: msg.to, size: audioBuffer.length }, "Sending audio reply");
        await sock.sendMessage(msg.to, {
          audio: audioBuffer,
          mimetype: msg.mimetype,
          ptt: msg.ptt,
        });
        break;
      }

      case "reply.image": {
        const imageBuffer = Buffer.from(msg.data, "base64");
        log.info({ to: msg.to, size: imageBuffer.length }, "Sending image reply");
        await sock.sendMessage(msg.to, {
          image: imageBuffer,
          mimetype: msg.mimetype,
          caption: msg.caption,
        });
        break;
      }

      case "ping": {
        // No-op, keep-alive acknowledged
        break;
      }

      default: {
        log.warn({ type: (msg as any).type }, "Unknown app message type");
      }
    }
  };
}
