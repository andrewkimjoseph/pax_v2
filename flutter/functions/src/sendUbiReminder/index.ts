import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { getMessaging, Message } from "firebase-admin/messaging";
import type { Address } from "viem";
import { DB } from "../../utils/config";
import { isWalletWhitelisted } from "../../utils/helpers/isWalletWhitelisted";

type PaxWalletDoc = {
  participantId?: string;
  eoAddress?: string;
};

type FcmTokenDoc = {
  participantId?: string;
  token?: string;
};

const CHUNK_SIZE = 200;
const MAX_SEND_EACH_BATCH = 500;

function chunkArray<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

export const sendUbiReminder = onSchedule(
  { schedule: "0 15 * * *", timeZone: "Africa/Nairobi" },
  async () => {
    const firestore = DB();
    logger.info("[UBI] Starting daily UBI reminder job");

    const snapshot = await firestore.collection("pax_wallets").get();

    const wallets: {
      id: string;
      participantId: string;
      eoAddress: Address;
    }[] = [];

    snapshot.forEach((doc) => {
      const data = doc.data() as PaxWalletDoc;
      if (!data.participantId || !data.eoAddress) {
        return;
      }
      wallets.push({
        id: doc.id,
        participantId: data.participantId,
        eoAddress: data.eoAddress as Address,
      });
    });

    logger.info("[UBI] Loaded pax_wallets candidates", {
      totalWallets: wallets.length,
    });

    const verifiedWallets: {
      id: string;
      participantId: string;
      eoAddress: Address;
    }[] = [];

    for (const batch of chunkArray(wallets, CHUNK_SIZE)) {
      const results = await Promise.allSettled(
        batch.map((wallet) => isWalletWhitelisted(wallet.eoAddress))
      );

      results.forEach((result, index) => {
        const wallet = batch[index];
        if (result.status === "fulfilled") {
          if (result.value) {
            verifiedWallets.push({
              id: wallet.id,
              participantId: wallet.participantId,
              eoAddress: wallet.eoAddress,
            });
          }
        } else {
          logger.error("[UBI] getWhitelistedRoot failed", {
            walletId: wallet.id,
            eoAddress: wallet.eoAddress,
            error: result.reason,
          });
        }
      });
    }

    if (verifiedWallets.length === 0) {
      logger.info("[UBI] No verified wallets for reminder today");
      return;
    }

    logger.info("[UBI] Verified wallets after on-chain check", {
      verifiedWallets: verifiedWallets.length,
    });

    const tokensByParticipant: Record<
      string,
      { token: string; walletId: string }
    > = {};

    const fcmSnapshot = await firestore.collection("fcm_tokens").get();
    const fcmTokens: { id: string; participantId: string; token: string }[] = [];
    fcmSnapshot.forEach((doc) => {
      const data = doc.data() as FcmTokenDoc;
      if (!data.participantId || !data.token) {
        return;
      }
      fcmTokens.push({
        id: doc.id,
        participantId: data.participantId,
        token: data.token,
      });
    });

    verifiedWallets.forEach((wallet) => {
      const candidateTokens = fcmTokens.filter(
        (t) => t.participantId === wallet.participantId
      );
      if (candidateTokens.length === 0) {
        return;
      }
      const latestToken = candidateTokens.reduce((acc, current) =>
        acc.id > current.id ? acc : current
      );
      tokensByParticipant[wallet.participantId] = {
        token: latestToken.token,
        walletId: wallet.id,
      };
    });

    const messages: {
      message: Message;
      participantId: string;
      walletId: string;
    }[] = [];

    Object.entries(tokensByParticipant).forEach(([participantId, entry]) => {
      const message: Message = {
        token: entry.token,
        notification: {
          title: "Time to claim your UBI",
          body: "Got to PaxWallet > Mini Apps > Claim G$ Daily to claim your daily reward.",
        },
      };
      messages.push({
        message,
        participantId,
        walletId: entry.walletId,
      });
    });

    if (messages.length === 0) {
      logger.info("[UBI] No messages to send (no tokens for verified wallets)");
      return;
    }

    logger.info("[UBI] Prepared messages for sendEach", {
      totalMessages: messages.length,
    });

    const messaging = getMessaging();

    for (const batch of chunkArray(messages, MAX_SEND_EACH_BATCH)) {
      const response = await messaging.sendEach(
        batch.map((entry) => entry.message)
      );

      logger.info("[UBI] sendEach batch result", {
        successCount: response.successCount,
        failureCount: response.failureCount,
      });

      response.responses.forEach((res, index) => {
        if (!res.success) {
          logger.error("[UBI] Failed to send UBI reminder", {
            error: res.error,
            participantId: batch[index]?.participantId,
          });
          return;
        }
      });
    }

    logger.info("[UBI] Finished daily UBI reminder job");
  }
);

