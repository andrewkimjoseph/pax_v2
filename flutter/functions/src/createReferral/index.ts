import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { DB, FUNCTION_RUNTIME_OPTS, REFERRAL_REWARD_AMOUNT } from "../../utils/config";
import { sendParticipantNotification } from "../../utils/helpers/sendNotification";

interface CreateReferralRequest {
  referringParticipantId?: string;
  referredParticipantId: string;
}

export const createReferral = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      if (!request.auth) {
        logger.error("Unauthenticated request to createReferral");
        throw new HttpsError(
          "unauthenticated",
          "The function must be called by an authenticated user."
        );
      }

      const { referringParticipantId, referredParticipantId } =
        request.data as CreateReferralRequest;

      if (!referredParticipantId) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: referredParticipantId"
        );
      }

      const authUid = request.auth.uid;
      if (authUid !== referredParticipantId) {
        logger.warn(
          "Referral: referredParticipantId does not match auth uid",
          { authUid, referredParticipantId }
        );
      }

      const firestore = DB();
      const now = FieldValue.serverTimestamp();

      // Prevent duplicate referrals for the same referrer/referred pair
      if (referringParticipantId) {
        const existingSnapshot = await firestore
          .collection("referrals")
          .where("referringParticipantId", "==", referringParticipantId)
          .where("referredParticipantId", "==", referredParticipantId)
          .limit(1)
          .get();

        if (!existingSnapshot.empty) {
          const existingId = existingSnapshot.docs[0].id;
          logger.info("Referral already exists, skipping create", {
            id: existingId,
            referringParticipantId,
            referredParticipantId,
          });
          return { id: existingId, duplicate: true };
        }
      }

      const referralsCollection = firestore.collection("referrals");
      const docRef = referralsCollection.doc();

      await docRef.set({
        id: docRef.id,
        referringParticipantId: referringParticipantId ?? null,
        referredParticipantId,
        amountReceived: REFERRAL_REWARD_AMOUNT,
        txnHash: null,
        timeCreated: now,
        timeUpdated: now,
        timeRewarded: null,
      });

      logger.info("Referral created", {
        id: docRef.id,
        referringParticipantId,
        referredParticipantId,
        amountReceived: REFERRAL_REWARD_AMOUNT,
      });

      if (referringParticipantId) {
        await sendParticipantNotification(
          referringParticipantId,
          "You have a new referral!",
          "Thank you for referring a friend. Check Activity > Referrals to claim the reward."
        );
      }

      return {
        id: docRef.id,
      };
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("createReferral error:", message);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        `Failed to create referral: ${
          error instanceof Error ? error.message : String(error)
        }`
      );
    }
  }
);

