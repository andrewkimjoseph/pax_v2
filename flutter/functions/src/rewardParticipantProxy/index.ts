import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import {
  Address,
  encodeFunctionData,
  http,
  parseEther,
  createWalletClient,
} from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { celo } from "viem/chains";
import { createViemAccount } from "@privy-io/server-auth/viem";
import { privateKeyToAccount } from "viem/accounts";
import { canvassingRewarderABI } from "../../utils/abis/new/canvassingRewarder";
import { taskManagerV1ABI } from "../../utils/abis/taskManagerV1ABI";
import {
  FUNCTION_RUNTIME_OPTS,
  PRIVY_CLIENT,
  PUBLIC_CLIENT,
  DB,
  AUTH,
  DRPC_URL,
  CANVASSING_REWARDER_ADDRESS,
  REWARD_TOKEN_ADDRESS,
  PIMLICO_URL,
} from "../../utils/config";
import { decryptPrivateKey } from "../../utils/helpers/decryptPrivateKey";
import {
  createTaskRewardClaimSignaturePackageCanvassing,
  createRewardClaimSignaturePackage,
  generateRandomNonce,
} from "../../utils/helpers/rewardingSignature";
import {
  createRewardRecord,
  updateRewardWithTxnHash,
} from "../../utils/helpers/createReward";
import { getReferralTagFromSmartAccount } from "../../utils/helpers/getReferralTagFromSmartAccount";

/**
 * Firebase onCall function to reward a participant after task completion.
 * This function replaces the Firestore trigger for more reliability.
 */
export const rewardParticipantProxy = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      // Ensure the user is authenticated
      if (!request.auth) {
        logger.error("Unauthenticated request to rewardParticipantProxy", {
          requestAuth: request.auth,
        });
        throw new HttpsError(
          "unauthenticated",
          "The function must be called by an authenticated user."
        );
      }

      const userId = request.auth.uid;
      // Check if the user is disabled
      const userRecord = await AUTH.getUser(userId);
      if (userRecord.disabled) {
        throw new HttpsError("permission-denied", "This user is disabled.");
      }

      const { taskCompletionId, encryptedPrivateKey, sessionKey, eoWalletAddress } =
        request.data as {
          taskCompletionId: string;
          encryptedPrivateKey?: string;
          sessionKey?: string;
          eoWalletAddress?: string;
        };

      if (!taskCompletionId) {
        logger.error("Missing taskCompletionId in rewardParticipantProxy", {
          taskCompletionId,
        });
        throw new HttpsError(
          "invalid-argument",
          "Missing taskCompletionId parameter."
        );
      }

      // Get task completion data
      const firestore = DB();
      const taskCompletionDoc = await firestore
        .collection("task_completions")
        .doc(taskCompletionId)
        .get();

      if (!taskCompletionDoc.exists) {
        logger.error("Task completion not found in rewardParticipantProxy", {
          taskCompletionId,
        });
        throw new HttpsError("not-found", "Task completion not found");
      }

      const taskCompletionData = taskCompletionDoc.data();
      if (!taskCompletionData) {
        logger.error(
          "Task completion data is empty in rewardParticipantProxy",
          { taskCompletionId }
        );
        throw new HttpsError("not-found", "Task completion data is empty");
      }

      // Validate that the task completion is valid for reward
      if (taskCompletionData.isValid === false) {
        logger.error("Attempted to claim reward for invalid task completion", {
          taskCompletionId,
          isValid: taskCompletionData.isValid,
        });
        throw new HttpsError(
          "failed-precondition",
          "Cannot claim reward for invalid task completion"
        );
      }

      // Extract required data from the task completion
      const { taskId, participantId } = taskCompletionData;
      if (!taskId || !participantId) {
        logger.error(
          "Task completion missing required fields in rewardParticipantProxy",
          { taskCompletionId, taskId, participantId }
        );
        throw new HttpsError(
          "invalid-argument",
          "Task completion missing required fields"
        );
      }

      logger.info("Starting participant reward process", {
        taskCompletionId,
        taskId,
        participantId,
      });

      // Step 1: Get required data from related collections
      // Get task data for reward details
      const taskDoc = await firestore.collection("tasks").doc(taskId).get();
      if (!taskDoc.exists) {
        logger.error("Task not found in rewardParticipantProxy", { taskId });
        throw new HttpsError("not-found", "Task not found");
      }

      const taskData = taskDoc.data();
      if (
        !taskData ||
        !taskData.rewardAmountPerParticipant ||
        !taskData.rewardCurrencyId
      ) {
        logger.error(
          "Task missing required reward data in rewardParticipantProxy",
          { taskId, taskData }
        );
        throw new HttpsError(
          "invalid-argument",
          "Task missing required reward data"
        );
      }

      const rewardAmountPerParticipant = taskData.rewardAmountPerParticipant;
      const rewardCurrencyId = taskData.rewardCurrencyId;
      const taskManagerContractAddress = taskData
        .managerContractAddress as Address | undefined;
      const taskMasterId = taskData.taskMasterId as string | undefined;

      // Get the participant's PaxAccount
      const participantPaxAccountDoc = await firestore
        .collection("pax_accounts")
        .doc(participantId)
        .get();
      if (!participantPaxAccountDoc.exists) {
        logger.error(
          "PaxAccount record not found for participant in rewardParticipantProxy",
          { participantId }
        );
        throw new HttpsError(
          "not-found",
          "PaxAccount record not found for participant"
        );
      }

      const participantPaxAccountData = participantPaxAccountDoc.data();
      const serverWalletId = participantPaxAccountData?.serverWalletId as
        | string
        | undefined;
      const contractAddress = participantPaxAccountData?.contractAddress as
        | string
        | undefined;
      const smartAccountWalletAddress = participantPaxAccountData
        ?.smartAccountWalletAddress as string | undefined;
      // Payout address: V1 = contract, V2 = smart account
      const paxAccountPayoutAddress = (contractAddress ||
        smartAccountWalletAddress) as Address | undefined;

      if (!paxAccountPayoutAddress) {
        logger.error(
          "Participant PaxAccount missing payout address (contractAddress or smartAccountWalletAddress) in rewardParticipantProxy",
          { participantId, participantPaxAccountData }
        );
        throw new HttpsError(
          "invalid-argument",
          "Participant PaxAccount missing payout address"
        );
      }

      const isV2 =
        !!encryptedPrivateKey && !!sessionKey && !!eoWalletAddress;

      if (!isV2) {
        logger.info("Using V1 Pimlico reward flow", {
          taskCompletionId,
          taskId,
          participantId,
        });

        if (!taskManagerContractAddress || !taskMasterId) {
          logger.error(
            "Task missing managerContractAddress or taskMasterId in V1 reward flow",
            { taskId, taskData }
          );
          throw new HttpsError(
            "invalid-argument",
            "Task missing required managerContractAddress or taskMasterId for V1 reward flow"
          );
        }

        if (!contractAddress || !serverWalletId) {
          logger.error(
            "Participant PaxAccount missing contractAddress or serverWalletId in V1 reward flow",
            { participantId, participantPaxAccountData }
          );
          throw new HttpsError(
            "invalid-argument",
            "Participant PaxAccount missing contractAddress or serverWalletId for V1 reward flow"
          );
        }

        const taskMasterPaxAccountDoc = await firestore
          .collection("pax_accounts")
          .doc(taskMasterId)
          .get();
        if (!taskMasterPaxAccountDoc.exists) {
          logger.error(
            "PaxAccount record not found for task master in rewardParticipantProxy (V1)",
            { taskMasterId }
          );
          throw new HttpsError(
            "not-found",
            "PaxAccount record not found for task master"
          );
        }

        const taskMasterPaxAccountData = taskMasterPaxAccountDoc.data();
        if (!taskMasterPaxAccountData?.serverWalletId) {
          logger.error(
            "Task master PaxAccount missing serverWalletId in rewardParticipantProxy (V1)",
            { taskMasterId, taskMasterPaxAccountData }
          );
          throw new HttpsError(
            "invalid-argument",
            "Task master PaxAccount missing serverWalletId"
          );
        }

        const taskMasterServerWalletId = taskMasterPaxAccountData.serverWalletId;

        const { createSmartAccountClient } = await import("permissionless");
        const { toSimpleSmartAccount } = await import(
          "permissionless/accounts"
        );
        const { createPimlicoClient } = await import(
          "permissionless/clients/pimlico"
        );

        const PIMLICO_CLIENT = createPimlicoClient({
          transport: http(PIMLICO_URL),
          entryPoint: {
            address: entryPoint07Address,
            version: "0.7",
          },
        });

        const [serverWallet, taskMasterWallet] = await Promise.all([
          PRIVY_CLIENT.walletApi.getWallet({ id: serverWalletId }),
          PRIVY_CLIENT.walletApi.getWallet({ id: taskMasterServerWalletId }),
        ]);

        if (!serverWallet) {
          logger.error(
            "Server wallet not found in rewardParticipantProxy (V1)",
            {
              serverWalletId,
            }
          );
          throw new HttpsError("not-found", "Server wallet not found");
        }

        if (!taskMasterWallet) {
          logger.error(
            "Task master wallet not found in rewardParticipantProxy (V1)",
            {
              taskMasterServerWalletId,
            }
          );
          throw new HttpsError("not-found", "Task master wallet not found");
        }

        const serverWalletAccount = await createViemAccount({
          walletId: serverWallet.id,
          address: serverWallet.address as Address,
          privy: PRIVY_CLIENT,
        });

        const smartAccount = await toSimpleSmartAccount({
          client: PUBLIC_CLIENT,
          owner: serverWalletAccount,
          entryPoint: {
            address: entryPoint07Address,
            version: "0.7",
          },
        });

        const participantProxy = smartAccount.address;
        logger.info("V1 smart account created", { participantProxy });

        const nonce = generateRandomNonce();

        logger.info("Generating V1 reward claim signature", {
          participantProxy,
          taskCompletionId,
          nonce: nonce.toString(),
        });

        const signaturePackage = await createRewardClaimSignaturePackage(
          taskManagerContractAddress,
          taskMasterWallet.id,
          taskMasterWallet.address as Address,
          participantProxy,
          taskCompletionId,
          nonce
        );

        if (!signaturePackage.isValid) {
          logger.error(
            "Signature validation failed in rewardParticipantProxy (V1)",
            {
              signaturePackage,
            }
          );
          throw new HttpsError("internal", "Signature validation failed");
        }

        const signature = signaturePackage.signature;
        const nonceString = signaturePackage.nonce;

        const smartAccountClient = createSmartAccountClient({
          account: smartAccount,
          chain: celo,
          bundlerTransport: http(PIMLICO_URL),
          paymaster: PIMLICO_CLIENT,
          userOperation: {
            estimateFeesPerGas: async () => {
              return (await PIMLICO_CLIENT.getUserOperationGasPrice()).fast;
            },
          },
        });

        const referralTag = getReferralTagFromSmartAccount(smartAccountClient);

        const rewardClaimData = encodeFunctionData({
          abi: taskManagerV1ABI,
          functionName: "processRewardClaimByParticipantProxy",
          args: [
            participantProxy,
            contractAddress as Address,
            taskCompletionId,
            nonce,
            signature,
          ],
        });

        logger.info("Submitting V1 reward claim transaction");

        const userOpTxnHash = await smartAccountClient.sendUserOperation({
          calls: [
            {
              to: taskManagerContractAddress,
              value: BigInt(0),
              data: (rewardClaimData + referralTag) as Address,
            },
          ],
        });

        logger.info("V1 transaction submitted", { userOpTxnHash });

        const userOpReceipt =
          await smartAccountClient.waitForUserOperationReceipt({
            hash: userOpTxnHash,
          });

        if (!userOpReceipt.success) {
          logger.error(
            "User operation failed in rewardParticipantProxy (V1)",
            {
              userOpReceipt,
            }
          );
          throw new HttpsError(
            "internal",
            `User operation failed: ${JSON.stringify(userOpReceipt)}`
          );
        }

        const bundleTxnHash = userOpReceipt.receipt.transactionHash;
        logger.info("V1 bundle transaction confirmed", { bundleTxnHash });

        const rewardRecordId = await createRewardRecord({
          taskId,
          participantId,
          taskCompletionId,
          signature,
          nonce: nonceString,
          amount: rewardAmountPerParticipant,
          rewardCurrencyId,
        });

        await updateRewardWithTxnHash(rewardRecordId, bundleTxnHash);

        logger.info(
          "V1 reward record created and updated with transaction hash",
          {
            rewardRecordId,
            bundleTxnHash,
          }
        );

        return {
          success: true,
          participantProxy,
          paxAccountContractAddress: contractAddress as Address,
          taskCompletionId,
          taskId,
          participantId,
          signature,
          nonce: nonceString,
          txnHash: bundleTxnHash,
          rewardRecordId,
          amount: rewardAmountPerParticipant,
          rewardCurrencyId,
        };
      }

      if (!CANVASSING_REWARDER_ADDRESS || CANVASSING_REWARDER_ADDRESS === "0x") {
        logger.error("CANVASSING_REWARDER_ADDRESS not configured");
        throw new HttpsError(
          "failed-precondition",
          "Reward service not configured. Missing CANVASSING_REWARDER_ADDRESS."
        );
      }

      logger.info("Using V2 CanvassingRewarder reward flow", {
        taskCompletionId,
        taskId,
        participantId,
      });

      if (userId !== participantId) {
        logger.error("Caller is not the participant (V2 reward)", {
          userId,
          participantId,
        });
        throw new HttpsError(
          "permission-denied",
          "Only the participant may claim their reward."
        );
      }
      if (!encryptedPrivateKey || !sessionKey || !eoWalletAddress) {
        logger.error(
          "V2 participant missing encryptedPrivateKey, sessionKey, or eoWalletAddress in rewardParticipantProxy",
          { participantId }
        );
        throw new HttpsError(
          "invalid-argument",
          "V2 participants must provide encryptedPrivateKey, sessionKey, and eoWalletAddress."
        );
      }

      type WalletAccount = Parameters<typeof createWalletClient>[0]["account"];
      let eoaAccount: WalletAccount;
      let eoAddress: Address;

      let privateKeyHex: string;
      try {
        privateKeyHex = decryptPrivateKey(encryptedPrivateKey, sessionKey);
        if (!privateKeyHex.startsWith("0x")) {
          privateKeyHex = "0x" + privateKeyHex;
        }
      } catch (error) {
        logger.error("Failed to decrypt private key (V2 reward)", { error });
        throw new HttpsError(
          "invalid-argument",
          "Failed to decrypt private key. Invalid session key or corrupted data."
        );
      }
      const account = privateKeyToAccount(privateKeyHex as `0x${string}`);
      if (account.address.toLowerCase() !== eoWalletAddress.toLowerCase()) {
        logger.error("EOA address mismatch (V2 reward)", {
          derived: account.address,
          provided: eoWalletAddress,
        });
        throw new HttpsError(
          "invalid-argument",
          "Private key does not match provided EOA address"
        );
      }
      eoaAccount = account;
      eoAddress = eoWalletAddress as Address;
      privateKeyHex = "";

      logger.info("EOA resolved for reward claim", { eoAddress });

      const amountWei = parseEther(String(rewardAmountPerParticipant));
      const nonce = generateRandomNonce();

      const signaturePackage =
        await createTaskRewardClaimSignaturePackageCanvassing(
          CANVASSING_REWARDER_ADDRESS,
          eoAddress,
          paxAccountPayoutAddress,
          taskId,
          REWARD_TOKEN_ADDRESS,
          amountWei,
          nonce
        );

      if (!signaturePackage.isValid) {
        logger.error("Signature validation failed in rewardParticipantProxy", {
          signaturePackage,
        });
        throw new HttpsError("internal", "Signature validation failed");
      }

      const signature = signaturePackage.signature;
      const nonceString = signaturePackage.nonce;

      const walletClient = createWalletClient({
        account: eoaAccount,
        chain: celo,
        transport: http(DRPC_URL),
      });

      const rewardClaimData = encodeFunctionData({
        abi: canvassingRewarderABI,
        functionName: "claimTaskReward",
        args: [
          eoAddress,
          paxAccountPayoutAddress,
          taskId,
          REWARD_TOKEN_ADDRESS,
          amountWei,
          nonce,
          signature,
        ],
      });

      logger.info("Submitting reward claim transaction (CanvassingRewarder)");

      const txHash = await walletClient.sendTransaction({
        to: CANVASSING_REWARDER_ADDRESS,
        data: rewardClaimData,
      });

      logger.info("Transaction submitted", { txHash });

      const receipt = await PUBLIC_CLIENT.waitForTransactionReceipt({
        hash: txHash,
      });

      const bundleTxnHash = receipt.transactionHash;
      logger.info("Bundle transaction confirmed", { bundleTxnHash });

      const rewardRecordId = await createRewardRecord({
        taskId,
        participantId,
        taskCompletionId,
        signature,
        nonce: nonceString,
        amount: rewardAmountPerParticipant,
        rewardCurrencyId,
      });

      await updateRewardWithTxnHash(rewardRecordId, bundleTxnHash);

      logger.info("Reward record created and updated with transaction hash", {
        rewardRecordId,
        bundleTxnHash,
      });

      return {
        success: true,
        participantProxy: paxAccountPayoutAddress,
        paxAccountContractAddress: paxAccountPayoutAddress,
        taskCompletionId,
        taskId,
        participantId,
        signature,
        nonce: nonceString,
        txnHash: bundleTxnHash,
        rewardRecordId,
        amount: rewardAmountPerParticipant,
        rewardCurrencyId,
      };
    } catch (error) {
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
