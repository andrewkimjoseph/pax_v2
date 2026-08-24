import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import type { Address } from "viem";
import { DB } from "../config";
import { isWalletWhitelisted } from "./isWalletWhitelisted";

const FACE_VERIFICATION_MESSAGE =
  "You need to complete GoodDollar face verification before participating in tasks.";

/**
 * Ensures the participant has at least one linked withdrawal wallet that is
 * GoodDollar whitelisted on-chain. Mirrors the client-side
 * ensureHasVerifiedWithdrawalMethod gate before screening.
 */
export async function requireParticipantHasVerifiedWithdrawalMethod(
  participantId: string
): Promise<void> {
  const snapshot = await DB()
    .collection("payment_methods")
    .where("participantId", "==", participantId)
    .get();

  if (snapshot.empty) {
    logger.warn("Participant has no withdrawal methods", { participantId });
    throw new HttpsError("failed-precondition", FACE_VERIFICATION_MESSAGE);
  }

  const walletAddresses: Address[] = [];
  for (const doc of snapshot.docs) {
    const walletAddress = doc.data()?.walletAddress as string | undefined;
    if (walletAddress && walletAddress.trim().startsWith("0x")) {
      walletAddresses.push(walletAddress as Address);
    }
  }

  if (walletAddresses.length === 0) {
    throw new HttpsError("failed-precondition", FACE_VERIFICATION_MESSAGE);
  }

  const results = await Promise.all(
    walletAddresses.map((addr) => isWalletWhitelisted(addr))
  );

  if (!results.some(Boolean)) {
    logger.warn("Participant has no GoodDollar-verified withdrawal method", {
      participantId,
      walletCount: walletAddresses.length,
    });
    throw new HttpsError("failed-precondition", FACE_VERIFICATION_MESSAGE);
  }
}
