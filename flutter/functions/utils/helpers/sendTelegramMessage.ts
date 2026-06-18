import { logger } from "firebase-functions/v2";
import { TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID } from "../config";

interface TelegramMessage {
  chat_id: string;
  text: string;
  parse_mode?: string;
}

interface SendTelegramMessageOptions {
  botToken?: string;
}

/**
 * Sends a message to Telegram using the configured bot token and chat ID
 * @param message - The Telegram message object
 * @returns Promise<void>
 */
export async function sendTelegramMessage(
  message: TelegramMessage,
  options?: SendTelegramMessageOptions
): Promise<void> {
  const botToken = options?.botToken || TELEGRAM_BOT_TOKEN;
  const chatId = message.chat_id || TELEGRAM_CHAT_ID;

  if (!botToken || !chatId) {
    logger.warn("Telegram bot token or chat ID not configured", {
      hasBotToken: !!botToken,
      hasChatId: !!chatId,
    });
    return;
  }

  try {
    logger.info("Sending Telegram message", {
      chatId,
      messageLength: message.text.length,
    });

    const response = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ...message, chat_id: chatId }),
    });

    if (!response.ok) {
      const errorData = await response.json();
      logger.error("Telegram API error", {
        status: response.status,
        statusText: response.statusText,
        errorData,
      });
      throw new Error(`Telegram API error: ${response.status} ${response.statusText}`);
    }

    const result = await response.json();
    logger.info("Telegram message sent successfully", {
      messageId: result.result?.message_id,
      chatId: result.result?.chat?.id,
    });
  } catch (error) {
    logger.error("Failed to send Telegram message", {
      error: error instanceof Error ? error.message : "Unknown error",
      stack: error instanceof Error ? error.stack : undefined,
    });
    throw error;
  }
}
