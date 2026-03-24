import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { DB } from "../config";

/**
 * Ensures recipientAddress belongs to the participant's saved withdrawal methods
 * (payment_methods collection). Case-insensitive address match.
 */
export async function assertRecipientIsUserWithdrawalMethod(
  participantId: string,
  recipientAddress: string
): Promise<void> {
  const normalized = recipientAddress.trim().toLowerCase();
  if (!normalized.startsWith("0x") || normalized.length < 42) {
    throw new HttpsError(
      "invalid-argument",
      "Invalid recipient wallet address."
    );
  }

  const snapshot = await DB()
    .collection("payment_methods")
    .where("participantId", "==", participantId)
    .get();

  for (const doc of snapshot.docs) {
    const wallet = doc.data()?.walletAddress as string | undefined;
    if (wallet && wallet.toLowerCase() === normalized) {
      return;
    }
  }

  logger.warn("Claim recipient not in user payment_methods", {
    participantId,
    recipientAddress: normalized,
  });
  throw new HttpsError(
    "permission-denied",
    "Recipient address must be one of your connected withdrawal wallets."
  );
}
