import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";

import { DB } from "../../utils/config";

// Create withdrawal record interface
interface WithdrawalParams {
  participantId: string;
  paymentMethodId: string;
  amountRequested: number;
  rewardCurrencyId: number;
  txnHash: string;
}

/**
 * Function to create a withdrawal record in the database
 */
export async function createWithdrawalRecord(
  params: WithdrawalParams,
  logPrefix?: "V1" | "V2"
): Promise<string> {
  try {
    const { 
      participantId, 
      paymentMethodId,
      amountRequested,
      rewardCurrencyId,
      txnHash
    } = params;
    const prefix = logPrefix ? `[${logPrefix}] ` : "";

    logger.info(`${prefix}Creating withdrawal record`, {
      participantId,
      paymentMethodId,
      amountRequested
    });
    
    // Get Firestore reference
    const firestore = DB();
    const withdrawalsCollection = firestore.collection('withdrawals');
    
    // Generate a unique ID for the withdrawal record
    const withdrawalDocRef = withdrawalsCollection.doc();
    const withdrawalId = withdrawalDocRef.id;
    
    // Save to Firestore with all fields and server timestamps
    await withdrawalDocRef.set({
      id: withdrawalId,
      participantId,
      paymentMethodId,
      amountRequested,
      rewardCurrencyId,
      txnHash,
      timeCreated: FieldValue.serverTimestamp(),
      timeRequested: FieldValue.serverTimestamp(),
      timeUpdated: FieldValue.serverTimestamp(),
    });

    logger.info(`${prefix}Withdrawal record created successfully`, {
      withdrawalId,
      participantId,
      paymentMethodId
    });
    
    return withdrawalId;
  } catch (error) {
    const prefix = logPrefix ? `[${logPrefix}] ` : "";
    logger.error(`${prefix}Error creating withdrawal record`, { error });
    throw error;
  }
} 