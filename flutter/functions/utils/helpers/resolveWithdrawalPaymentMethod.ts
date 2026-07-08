import { DB } from "../config";

/**
 * Resolves a participant payment_methods document id by wallet address.
 * Returns null when no matching wallet is found.
 */
export async function resolveWithdrawalPaymentMethodIdByRecipient(
  participantId: string,
  recipientAddress: string
): Promise<string | null> {
  const normalized = recipientAddress.trim().toLowerCase();
  if (!normalized) {
    return null;
  }

  const snapshot = await DB()
    .collection("payment_methods")
    .where("participantId", "==", participantId)
    .get();

  for (const doc of snapshot.docs) {
    const walletAddress = doc.data()?.walletAddress as string | undefined;
    if (walletAddress && walletAddress.trim().toLowerCase() === normalized) {
      return doc.id;
    }
  }

  return null;
}
