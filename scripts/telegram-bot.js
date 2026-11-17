import https from "https";
import dotenv from "dotenv";
dotenv.config();

/**
 * Lasavo Institutional Telegram Deal Desk & Vault Monitor
 * Sends instant alerts on incoming USDC deposits, data room requests, and investor leads.
 */
export async function sendTelegramAlert(message) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID;

  if (!token || !chatId) {
    console.log("[Telegram] Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in .env to enable live alerts.");
    console.log("[Telegram] Alert preview:\n" + message);
    return false;
  }

  const url = `https://api.telegram.org/bot${token}/sendMessage`;
  const payload = JSON.stringify({
    chat_id: chatId,
    text: message,
    parse_mode: "Markdown"
  });

  return new Promise((resolve) => {
    const req = https.request(
      url,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payload)
        }
      },
      (res) => {
        let body = "";
        res.on("data", (chunk) => (body += chunk));
        res.on("end", () => {
          console.log("[Telegram] Alert sent successfully:", body);
          resolve(true);
        });
      }
    );

    req.on("error", (e) => {
      console.error("[Telegram] Error sending alert:", e.message);
      resolve(false);
    });

    req.write(payload);
    req.end();
  });
}

// Direct execution test
sendTelegramAlert(
  "🏛️ *Lasavo Deal Desk Initialized*\n\n" +
  "• *Platform:* Lasavo Yield (https://lasavo-yield.netlify.app)\n" +
  "• *Facility:* $5.0M Senior Secured On-Chain Facility\n" +
  "• *Status:* 24/7 Deal Alert Listening Active"
);
