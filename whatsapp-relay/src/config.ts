import "dotenv/config";

export const config = {
  wsPort: parseInt(process.env.WS_PORT || "8080", 10),
  httpPort: parseInt(process.env.HTTP_PORT || "8081", 10),
  allowedIp: process.env.ALLOWED_IP || "*",
  targetJid: process.env.TARGET_JID || "",
  logLevel: (process.env.LOG_LEVEL || "info") as
    | "fatal"
    | "error"
    | "warn"
    | "info"
    | "debug"
    | "trace",
  authDir: ".auth",
} as const;
