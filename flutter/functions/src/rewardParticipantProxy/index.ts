import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { Address, encodeFunctionData, parseEther } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { createViemAccount } from "@privy-io/server-auth/viem";
import { privateKeyToAccount } from "viem/accounts";
import { canvassingRewarderABI } from "../../utils/abis/new/canvassingRewarder";
import {
  FUNCTION_RUNTIME_OPTS,
  PUBLIC_CLIENT,
  DB,
  AUTH,
  CANVASSING_REWARDER_PROXY_ADDRESS,
  REWARD_TOKEN_ADDRESS,
  PRIVY_CLIENT,
} from "../../utils/config";
import { decryptPrivateKey } from "../../utils/helpers/decryptPrivateKey";
import {
  createTaskRewardClaimSignaturePackageCanvassing,
  generateRandomNonce,
} from "../../utils/helpers/rewardingSignature";
import {
  createRewardRecord,
  updateRewardWithTxnHash,
} from "../../utils/helpers/createReward";
import { submitSponsoredRewarderCall } from "../../utils/helpers/submitSponsoredRewarderCall";

function isHttpsError(e: unknown): e is HttpsError {
  return (
    typeof e === "object" &&
    e !== null &&
    "code" in e &&
    typeof (e as HttpsError).code === "string"
  );
}

/**
 * V1: serverWalletId + Privy -> toSimpleSmartAccount (same as screenParticipantProxy).
 *     Payout/caller = derived smart account address (not PaxAccount.contractAddress).
 *     If PaxAccount.smartAccountWalletAddress is set, it must match derived address.
 * V2: decrypted EOA + PaxAccount payout address + Pimlico (eoAddress = user EOA).
 */
export const rewardParticipantProxy = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError(
          "unauthenticated",
          "The function must be called by an authenticated user."
        );
      }

      const userId = request.auth.uid;
      const userRecord = await AUTH.getUser(userId);
      if (userRecord.disabled) {
        throw new HttpsError("permission-denied", "This user is disabled.");
      }

      const {
        taskCompletionId,
        serverWalletId,
        encryptedPrivateKey,
        sessionKey,
        eoWalletAddress,
      } = request.data as {
        taskCompletionId: string;
        serverWalletId?: string;
        encryptedPrivateKey?: string;
        sessionKey?: string;
        eoWalletAddress?: string;
      };

      if (!taskCompletionId) {
        throw new HttpsError(
          "invalid-argument",
          "Missing taskCompletionId parameter."
        );
      }

      const isV2 =
        !serverWalletId &&
        !!encryptedPrivateKey &&
        !!sessionKey &&
        !!eoWalletAddress;
      const isV1 = !!serverWalletId;

      if (!isV1 && !isV2) {
        throw new HttpsError(
          "invalid-argument",
          "Provide serverWalletId (V1) or encryptedPrivateKey, sessionKey, and eoWalletAddress (V2)."
        );
      }

      if (
        !CANVASSING_REWARDER_PROXY_ADDRESS ||
        CANVASSING_REWARDER_PROXY_ADDRESS === "0x"
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Reward service not configured. Missing CANVASSING_REWARDER_PROXY_ADDRESS."
        );
      }

      const firestore = DB();
      const taskCompletionDoc = await firestore
        .collection("task_completions")
        .doc(taskCompletionId)
        .get();

      if (!taskCompletionDoc.exists) {
        throw new HttpsError("not-found", "Task completion not found");
      }

      const taskCompletionData = taskCompletionDoc.data();
      if (!taskCompletionData) {
        throw new HttpsError("not-found", "Task completion data is empty");
      }

      if (taskCompletionData.isValid === false) {
        throw new HttpsError(
          "failed-precondition",
          "Cannot claim reward for invalid task completion"
        );
      }

      const { taskId, participantId } = taskCompletionData;
      if (!taskId || !participantId) {
        throw new HttpsError(
          "invalid-argument",
          "Task completion missing required fields"
        );
      }

      if (userId !== participantId) {
        throw new HttpsError(
          "permission-denied",
          "Only the participant may claim their reward."
        );
      }

      const taskDoc = await firestore.collection("tasks").doc(taskId).get();
      if (!taskDoc.exists) {
        throw new HttpsError("not-found", "Task not found");
      }

      const taskData = taskDoc.data();
      if (
        !taskData ||
        !taskData.rewardAmountPerParticipant ||
        !taskData.rewardCurrencyId
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Task missing required reward data"
        );
      }

      const rewardAmountPerParticipant = taskData.rewardAmountPerParticipant;
      const rewardCurrencyId = taskData.rewardCurrencyId;

      const participantPaxAccountDoc = await firestore
        .collection("pax_accounts")
        .doc(participantId)
        .get();
      if (!participantPaxAccountDoc.exists) {
        throw new HttpsError(
          "not-found",
          "PaxAccount record not found for participant"
        );
      }

      const participantPaxAccountData = participantPaxAccountDoc.data();
      const smartAccountWalletAddress = participantPaxAccountData
        ?.smartAccountWalletAddress as string | undefined;
      const contractAddress = participantPaxAccountData?.contractAddress as
        | string
        | undefined;
      /** V2: payout AA address (EOA-derived). V1: set after Privy smart account build (same as screening). */
      let paxAccountPayoutAddress: Address;

      const { toSimpleSmartAccount } = await import("permissionless/accounts");
      const amountWei = parseEther(String(rewardAmountPerParticipant));
      const nonce = generateRandomNonce();

      let eoAddress: Address;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      let smartAccount: any;
      let logPrefix: string;

      if (isV1) {
        logPrefix = "[V1]";
        const serverWallet = await PRIVY_CLIENT.walletApi.getWallet({
          id: serverWalletId!,
        });
        if (!serverWallet) {
          throw new HttpsError("not-found", "Server wallet not found");
        }
        const serverWalletAccount = await createViemAccount({
          walletId: serverWallet.id,
          address: serverWallet.address as Address,
          privy: PRIVY_CLIENT,
        });
        smartAccount = await toSimpleSmartAccount({
          client: PUBLIC_CLIENT,
          owner: serverWalletAccount,
          entryPoint: {
            address: entryPoint07Address,
            version: "0.7",
          },
        });
        // Same derivation as screenParticipantProxy V1; checkIfScreened(taskId, msg.sender) uses this address.
        paxAccountPayoutAddress = smartAccount.address as Address;
        if (smartAccountWalletAddress) {
          if (
            smartAccount.address.toLowerCase() !==
            smartAccountWalletAddress.toLowerCase()
          ) {
            logger.error(
              `${logPrefix} Smart account mismatch vs PaxAccount.smartAccountWalletAddress`,
              {
                derived: smartAccount.address,
                smartAccountWalletAddress,
              }
            );
            throw new HttpsError(
              "failed-precondition",
              "serverWalletId does not match PaxAccount smartAccountWalletAddress."
            );
          }
        }
        eoAddress = serverWallet.address as Address;
      } else {
        logPrefix = "[V2]";
        paxAccountPayoutAddress = (contractAddress ||
          smartAccountWalletAddress) as Address;
        if (!paxAccountPayoutAddress) {
          throw new HttpsError(
            "invalid-argument",
            "V2 PaxAccount missing contractAddress or smartAccountWalletAddress"
          );
        }
        let privateKeyHex: string;
        try {
          privateKeyHex = decryptPrivateKey(
            encryptedPrivateKey!,
            sessionKey!
          );
          if (!privateKeyHex.startsWith("0x")) {
            privateKeyHex = "0x" + privateKeyHex;
          }
        } catch (error) {
          logger.error("[V2] Decrypt failed (reward)", { error });
          throw new HttpsError(
            "invalid-argument",
            "Failed to decrypt private key."
          );
        }
        const eoaAccount = privateKeyToAccount(privateKeyHex as `0x${string}`);
        if (
          eoaAccount.address.toLowerCase() !== eoWalletAddress!.toLowerCase()
        ) {
          throw new HttpsError(
            "invalid-argument",
            "Private key does not match eoWalletAddress"
          );
        }
        privateKeyHex = "";
        smartAccount = await toSimpleSmartAccount({
          client: PUBLIC_CLIENT,
          owner: eoaAccount,
          entryPoint: {
            address: entryPoint07Address,
            version: "0.7",
          },
        });
        if (
          smartAccount.address.toLowerCase() !==
          paxAccountPayoutAddress.toLowerCase()
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Wallet smart account does not match PaxAccount payout address."
          );
        }
        eoAddress = eoWalletAddress as Address;
      }

      const smartAaAddress = smartAccount.address as Address;
      const recipientAddress: Address = isV1
        ? ((contractAddress as Address) || smartAaAddress)
        : smartAaAddress;

      const signaturePackage =
        await createTaskRewardClaimSignaturePackageCanvassing(
          CANVASSING_REWARDER_PROXY_ADDRESS,
          eoAddress,
          smartAaAddress,
          recipientAddress,
          taskId,
          REWARD_TOKEN_ADDRESS,
          amountWei,
          nonce
        );

      if (!signaturePackage.isValid) {
        throw new HttpsError("internal", "Signature validation failed");
      }

      const rewardClaimData = encodeFunctionData({
        abi: canvassingRewarderABI,
        functionName: "claimTaskReward",
        args: [
          eoAddress,
          smartAaAddress,
          recipientAddress,
          taskId,
          REWARD_TOKEN_ADDRESS,
          amountWei,
          nonce,
          signaturePackage.signature,
        ],
      });

      const { bundleTxnHash } = await submitSponsoredRewarderCall({
        smartAccount,
        data: rewardClaimData,
        logPrefix,
      });

      const nonceString = signaturePackage.nonce;
      const rewardRecordId = await createRewardRecord({
        taskId,
        participantId,
        taskCompletionId,
        signature: signaturePackage.signature,
        nonce: nonceString,
        amount: rewardAmountPerParticipant,
        rewardCurrencyId,
        logPrefix: isV2 ? "V2" : "V1",
      });

      await updateRewardWithTxnHash(
        rewardRecordId,
        bundleTxnHash,
        isV2 ? "V2" : "V1"
      );

      return {
        success: true,
        participantProxy: smartAaAddress,
        paxAccountContractAddress: recipientAddress,
        taskCompletionId,
        taskId,
        participantId,
        signature: signaturePackage.signature,
        nonce: nonceString,
        txnHash: bundleTxnHash,
        rewardRecordId,
        amount: rewardAmountPerParticipant,
        rewardCurrencyId,
      };
    } catch (error) {
      if (isHttpsError(error)) throw error;
      logger.error("Reward process failed", { error });
      throw new HttpsError(
        "internal",
        `Failed to reward participant: ${
          error instanceof Error ? error.message : "Unknown error"
        }`
      );
    }
  }
);
