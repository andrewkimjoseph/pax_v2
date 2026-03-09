// src/screenParticipantProxy/index.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { Address, encodeFunctionData, http } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { celo } from "viem/chains";
import { createViemAccount } from "@privy-io/server-auth/viem";
import { privateKeyToAccount } from "viem/accounts";
import { FieldValue } from "firebase-admin/firestore";

import { canvassingTaskManagerABI } from "../../utils/abis/new/canvassingTaskManager";
import {
  FUNCTION_RUNTIME_OPTS,
  PRIVY_CLIENT,
  PUBLIC_CLIENT,
  PIMLICO_URL,
  DB,
  AUTH,
  CANVASSING_TASK_MANAGER_PROXY_ADDRESS,
} from "../../utils/config";
import { decryptPrivateKey } from "../../utils/helpers/decryptPrivateKey";
import {
  createScreeningSignaturePackageCanvassing,
  generateRandomNonce,
} from "../../utils/helpers/screeningSignature";
import { createScreeningRecord } from "../../utils/helpers/createScreening";
/**
 * Comprehensive cloud function to screen a participant
 * This function handles the complete process:
 * 1. Generates a signature for screening
 * 2. Submits the transaction to the blockchain
 * 3. Creates a screening record with the transaction hash
 * 4. Creates a task completion record associated with the screening
 *
 * Returns all relevant data including the participant proxy address,
 * signature, nonce, transaction hash, screening record ID, and task completion ID.
 */
export const screenParticipantProxy = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
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
      const { createSmartAccountClient } = await import("permissionless");
      const { toSimpleSmartAccount } = await import("permissionless/accounts");
      // Ensure the user is authenticated
      if (!request.auth) {
        logger.error("Unauthenticated request to screenParticipantProxy", {
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

      const {
        serverWalletId,
        taskId,
        participantId,
        taskMasterServerWalletId,
        // V2 path: ephemeral key (when participant has no Privy server wallet)
        encryptedPrivateKey,
        sessionKey,
        eoWalletAddress,
      } = request.data as {
        serverWalletId?: string;
        taskId: string;
        participantId: string;
        taskMasterServerWalletId: string;
        encryptedPrivateKey?: string;
        sessionKey?: string;
        eoWalletAddress?: string;
      };

      // Caller must be the participant
      if (userId !== participantId) {
        logger.error("Caller is not the participant", { userId, participantId });
        throw new HttpsError(
          "permission-denied",
          "Only the participant may screen themselves."
        );
      }

      // Validate: either V1 (serverWalletId) or V2 (encrypted key params)
      const isV2 =
        !serverWalletId &&
        !!encryptedPrivateKey &&
        !!sessionKey &&
        !!eoWalletAddress;
      const isV1 = !!serverWalletId;

      if (
        !taskId ||
        !participantId ||
        !taskMasterServerWalletId
      ) {
        logger.error("Missing required parameters in screenParticipantProxy", {
          serverWalletId,
          taskId,
          participantId,
          taskMasterServerWalletId,
        });
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameters: taskId, participantId, taskMasterServerWalletId."
        );
      }

      if (!CANVASSING_TASK_MANAGER_PROXY_ADDRESS || CANVASSING_TASK_MANAGER_PROXY_ADDRESS === "0x") {
        logger.error("CANVASSING_TASK_MANAGER_PROXY_ADDRESS not configured");
        throw new HttpsError(
          "failed-precondition",
          "Screening service not configured. Missing CANVASSING_TASK_MANAGER_PROXY_ADDRESS."
        );
      }

      if (!isV1 && !isV2) {
        logger.error(
          "Either serverWalletId (V1) or encryptedPrivateKey+sessionKey+eoWalletAddress (V2) required",
          { serverWalletId, hasV2Params: !!encryptedPrivateKey }
        );
        throw new HttpsError(
          "invalid-argument",
          "Provide serverWalletId for V1, or encryptedPrivateKey, sessionKey, and eoWalletAddress for V2."
        );
      }

      logger.info("Starting comprehensive participant screening process", {
        userId,
        taskId,
        participantId,
        isV2,
      });

      let smartAccount: Awaited<ReturnType<typeof toSimpleSmartAccount>>;

      if (isV1) {
        // V1: participant's Privy server wallet -> smart account
        const serverWallet = await PRIVY_CLIENT.walletApi.getWallet({
          id: serverWalletId!,
        });
        if (!serverWallet) {
          logger.error("[V1] Server wallet not found in screenParticipantProxy", {
            serverWalletId,
          });
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
      } else {
        // V2: decrypt EOA key from request, build smart account
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
          logger.error("[V2] Failed to decrypt private key (V2 screening)", {
            error,
          });
          throw new HttpsError(
            "invalid-argument",
            "Failed to decrypt private key. Invalid session key or corrupted data."
          );
        }
        const eoaAccount = privateKeyToAccount(privateKeyHex as `0x${string}`);
        if (
          eoaAccount.address.toLowerCase() !== eoWalletAddress!.toLowerCase()
        ) {
          logger.error("[V2] EOA address mismatch (V2 screening)", {
            derived: eoaAccount.address,
            provided: eoWalletAddress,
          });
          throw new HttpsError(
            "invalid-argument",
            "Private key does not match provided EOA address"
          );
        }
        smartAccount = await toSimpleSmartAccount({
          client: PUBLIC_CLIENT,
          owner: eoaAccount,
          entryPoint: {
            address: entryPoint07Address,
            version: "0.7",
          },
        });
        privateKeyHex = "";
      }

      const participantProxy = smartAccount.address;
      const logPrefix = isV2 ? "[V2]" : "[V1]";
      logger.info(`${logPrefix} Smart account created`, { participantProxy });

      // Step 2: Generate screening signature
      const nonce = generateRandomNonce();

      logger.info(`${logPrefix} Generating screening signature`, {
        participantProxy,
        taskId,
        nonce: nonce.toString(),
      });

      const signaturePackage = await createScreeningSignaturePackageCanvassing(
        CANVASSING_TASK_MANAGER_PROXY_ADDRESS,
        participantProxy,
        taskId,
        nonce,
        isV2 ? "V2" : "V1"
      );

      if (!signaturePackage.isValid) {
        logger.error(
          `${logPrefix} Generated signature failed verification in screenParticipantProxy`,
          { signaturePackage }
        );
        throw new HttpsError(
          "internal",
          "Generated signature failed verification"
        );
      }

      const signature = signaturePackage.signature;
      const nonceString = signaturePackage.nonce;

      // Step 3: Submit screening transaction
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

      const screeningData = encodeFunctionData({
        abi: canvassingTaskManagerABI,
        functionName: "screenParticipantProxy",
        args: [participantProxy, taskId, nonce, signature],
      });

      logger.info(`${logPrefix} Submitting screening transaction`);

      const userOpTxnHash = await smartAccountClient.sendUserOperation({
        calls: [
          {
            to: CANVASSING_TASK_MANAGER_PROXY_ADDRESS,
            value: BigInt(0),
            data: screeningData,
          },
        ],
      });

      logger.info(`${logPrefix} Transaction submitted`, { userOpTxnHash });

      const userOpReceipt =
        await smartAccountClient.waitForUserOperationReceipt({
          hash: userOpTxnHash,
        });

      if (!userOpReceipt.success) {
        logger.error(`${logPrefix} User operation failed in screenParticipantProxy`, {
          userOpReceipt,
        });
        throw new HttpsError(
          "internal",
          `User operation failed: ${JSON.stringify(userOpReceipt)}`
        );
      }

      // const txnHash = userOpReceipt.userOpHash;
      // logger.info("Transaction confirmed", { txnHash });

      const bundleTxnHash = userOpReceipt.receipt.transactionHash;
      logger.info(`${logPrefix} Bundle transaction confirmed`, { bundleTxnHash });

      // Step 4: Create screening record using the utility function
      const screeningId = await createScreeningRecord({
        taskId,
        participantId,
        signature,
        nonce: nonceString,
        txnHash: bundleTxnHash,
      }, isV2 ? "V2" : "V1");

      logger.info(`${logPrefix} Screening record created`, { screeningId });

      // Step 5: Create task completion record directly
      const firestore = DB();
      const taskCompletionsCollection =
        firestore.collection("task_completions");

      // Generate a unique ID for the task completion
      const taskCompletionDocRef = taskCompletionsCollection.doc();
      const taskCompletionId = taskCompletionDocRef.id;

      // Create the task completion record
      await taskCompletionDocRef.set({
        id: taskCompletionId,
        taskId,
        screeningId,
        participantId,
        timeCompleted: null, // Task is not yet completed
        timeCreated: FieldValue.serverTimestamp(),
        timeUpdated: FieldValue.serverTimestamp(),
      });

      logger.info(`${logPrefix} Task completion created successfully`, {
        taskCompletionId,
        screeningId,
        taskId,
        participantId,
      });

      // Return complete response with all relevant data
      return {
        success: true,
        participantProxy,
        taskId,
        signature,
        nonce: nonceString,
        txnHash: bundleTxnHash,
        screeningId,
        taskCompletionId, // Added task completion ID to the response
      };
    } catch (error) {
      logger.error("Comprehensive screening process failed", { error });

      throw new HttpsError(
        "internal",
        `Failed to screen participant: ${
          error instanceof Error ? error.message : "Unknown error"
        }`
      );
    }
  }
);
