import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { DB } from "../../utils/config";

interface DonationParams {
  participantId: string;
  amountDonated: number;
  collectiveDonatedTo: string;
  txnHash: string;
}

export async function createDonationRecord(
  params: DonationParams
): Promise<string> {
  try {
    const { participantId, amountDonated, collectiveDonatedTo, txnHash } = params;
    const firestore = DB();
    const donationsCollection = firestore.collection("donations");
    const donationDocRef = donationsCollection.doc();
    const donationId = donationDocRef.id;

    await donationDocRef.set({
      id: donationId,
      amountDonated,
      collectiveDonatedTo,
      participantId,
      timeDonated: FieldValue.serverTimestamp(),
      txnHash,
      timeCreated: FieldValue.serverTimestamp(),
      timeUpdated: FieldValue.serverTimestamp(),
    });

    logger.info("Donation record created successfully", {
      donationId,
      participantId,
      amountDonated,
      collectiveDonatedTo,
    });

    return donationId;
  } catch (error) {
    logger.error("Error creating donation record", { error });
    throw error;
  }
}
