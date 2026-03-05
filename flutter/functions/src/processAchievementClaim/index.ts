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
import { privateKeyToAccount } from "viem/accounts";
import {
  FUNCTION_RUNTIME_OPTS,
  PUBLIC_CLIENT,
  DB,
  AUTH,
  DRPC_URL,
  CANVASSING_REWARDER_ADDRESS,
  REWARD_TOKEN_ADDRESS,
  PIMLICO_URL,
  PAX_MASTER_PRIVATE_KEY_ACCOUNT,
} from "../../utils/config";
import { erc20ABI } from "../../utils/abis/erc20";
import { decryptPrivateKey } from "../../utils/helpers/decryptPrivateKey";
import {
  createAchievementRewardClaimSignaturePackageCanvassing,
  generateRandomNonce,
} from "../../utils/helpers/rewardingSignature";
import { canvassingRewarderABI } from "../../utils/abis/new/canvassingRewarder";
import { getReferralTagFromSmartAccount } from "../../utils/helpers/getReferralTagFromSmartAccount";

export const processAchievementClaim = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      if (!request.auth) {
        logger.error("Unauthenticated request to processAchievementClaim", {
          requestAuth: request.auth,
        });
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

      logger.info("Processing achievement claim for user:", {
        userId,
        achievementId: request.data?.achievementId,
      });

      const {
        achievementId,
        paxAccountContractAddress,
        amountEarned,
        tasksCompleted,
        eoWalletAddress,
        encryptedPrivateKey,
        sessionKey,
      } = request.data as {
        achievementId: string;
        paxAccountContractAddress: string;
        amountEarned: number;
        tasksCompleted: number;
        eoWalletAddress?: string;
        encryptedPrivateKey?: string;
        sessionKey?: string;
      };

      if (
        !achievementId ||
        !paxAccountContractAddress ||
        amountEarned === undefined ||
        tasksCompleted === undefined
      ) {
        logger.error("Missing required parameters in processAchievementClaim", {
          achievementId,
          paxAccountContractAddress,
          amountEarned,
          tasksCompleted,
        });
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameters: achievementId, paxAccountContractAddress, amountEarned, tasksCompleted."
        );
      }

      const firestore = DB();
      const achievementDoc = await firestore
        .collection("achievements")
        .doc(achievementId)
        .get();

      if (!achievementDoc.exists) {
        logger.error("Achievement not found in processAchievementClaim", {
          achievementId,
        });
        throw new HttpsError("not-found", "Achievement not found.");
      }

      const achievementData = achievementDoc.data();
      if (achievementData?.txnHash && achievementData?.timeClaimed) {
        logger.error("Achievement already claimed in processAchievementClaim", {
          achievementId,
          txnHash: achievementData.txnHash,
          timeClaimed: achievementData.timeClaimed,
        });
        throw new HttpsError(
          "already-exists",
          "Achievement has already been claimed."
        );
      }

      const smartAccountContractAddress = paxAccountContractAddress as Address;

      const isV2 = !!eoWalletAddress && !!encryptedPrivateKey && !!sessionKey;

      if (isV2) {
        if (
          !CANVASSING_REWARDER_ADDRESS ||
          CANVASSING_REWARDER_ADDRESS === "0x"
        ) {
          logger.error("CANVASSING_REWARDER_ADDRESS not configured");
          throw new HttpsError(
            "failed-precondition",
            "Achievement claim service not configured. Missing CANVASSING_REWARDER_ADDRESS."
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
          logger.error("Failed to decrypt private key (achievement claim)", {
            error,
          });
          throw new HttpsError(
            "invalid-argument",
            "Failed to decrypt private key. Invalid session key or corrupted data."
          );
        }
        const account = privateKeyToAccount(privateKeyHex as `0x${string}`);
        if (account.address.toLowerCase() !== eoWalletAddress.toLowerCase()) {
          logger.error("EOA address mismatch (achievement claim)", {
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
        logger.info("Using V2 CanvassingRewarder achievement claim flow", {
          userId,
          achievementId,
          smartAccountContractAddress,
          eoAddress,
        });

        const amountWei = parseEther(String(amountEarned));
        const nonce = generateRandomNonce();

        const signaturePackage =
          await createAchievementRewardClaimSignaturePackageCanvassing(
            CANVASSING_REWARDER_ADDRESS,
            eoAddress,
            smartAccountContractAddress,
            achievementId,
            REWARD_TOKEN_ADDRESS,
            amountWei,
            nonce
          );

        if (!signaturePackage.isValid) {
          logger.error("Achievement claim signature validation failed", {
            signaturePackage,
          });
          throw new HttpsError("internal", "Signature validation failed");
        }

        const walletClient = createWalletClient({
          account: eoaAccount,
          chain: celo,
          transport: http(DRPC_URL),
        });

        const data = encodeFunctionData({
          abi: canvassingRewarderABI,
          functionName: "claimAchievementReward",
          args: [
            eoAddress,
            smartAccountContractAddress,
            achievementId,
            REWARD_TOKEN_ADDRESS,
            amountWei,
            nonce,
            signaturePackage.signature,
          ],
        });

        logger.info(
          "Submitting achievement claim transaction (CanvassingRewarder, V2)"
        );

        const txHash = await walletClient.sendTransaction({
          to: CANVASSING_REWARDER_ADDRESS,
          data,
        });

        logger.info("Achievement claim transaction submitted (V2)", { txHash });

        const receipt = await PUBLIC_CLIENT.waitForTransactionReceipt({
          hash: txHash,
        });

        const bundleTxnHash = receipt.transactionHash;
        logger.info("Achievement claim transaction confirmed (V2)", {
          bundleTxnHash,
          achievementId,
        });

        await firestore.collection("achievements").doc(achievementId).update({
          txnHash: bundleTxnHash,
          timeClaimed: new Date(),
        });

        return { success: true, txnHash: bundleTxnHash };
      } else {
        logger.info("Using V1 Pimlico achievement claim flow", {
          userId,
          achievementId,
          paxAccountContractAddress,
        });

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

        const recipientAddress = smartAccountContractAddress;

        logger.info("Preparing V1 achievement claim transaction", {
          recipientAddress,
          amountEarned: amountEarned.toString(),
          rewardTokenAddress: REWARD_TOKEN_ADDRESS,
        });

        const paxMasterSmartAccount = await toSimpleSmartAccount({
          client: PUBLIC_CLIENT,
          owner: PAX_MASTER_PRIVATE_KEY_ACCOUNT,
          entryPoint: {
            address: entryPoint07Address,
            version: "0.7",
          },
        });

        logger.info("V1 Smart Account Address:", {
          address: paxMasterSmartAccount.address,
        });

        const balanceBefore = (await PUBLIC_CLIENT.readContract({
          address: REWARD_TOKEN_ADDRESS,
          abi: erc20ABI,
          functionName: "balanceOf",
          args: [recipientAddress],
        })) as bigint;

        logger.info("G$ Balance before transfer:", {
          address: recipientAddress,
          balance: balanceBefore.toString(),
        });

        const data = encodeFunctionData({
          abi: erc20ABI,
          functionName: "transfer",
          args: [recipientAddress, parseEther(amountEarned.toString())],
        });

        logger.info("Encoded V1 achievement claim transaction data");

        const smartAccountClient = createSmartAccountClient({
          account: paxMasterSmartAccount,
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

        const userOpTxnHash = await smartAccountClient.sendUserOperation({
          calls: [
            {
              to: REWARD_TOKEN_ADDRESS,
              data: (data + referralTag) as Address,
            },
          ],
        });

        logger.info("V1 user operation submitted", { userOpTxnHash });

        const userOpReceipt =
          await smartAccountClient.waitForUserOperationReceipt({
            hash: userOpTxnHash,
          });

        if (!userOpReceipt.success) {
          logger.error("User operation failed in processAchievementClaim (V1)", {
            userOpReceipt,
          });
          throw new HttpsError(
            "internal",
            `User operation failed: ${JSON.stringify(userOpReceipt)}`
          );
        }

        const bundleTxnHash = userOpReceipt.receipt.transactionHash;
        logger.info("V1 bundle transaction confirmed", { bundleTxnHash });

        await firestore.collection("achievements").doc(achievementId).update({
          txnHash: bundleTxnHash,
          timeClaimed: new Date(),
        });

        const balanceAfter = (await PUBLIC_CLIENT.readContract({
          address: REWARD_TOKEN_ADDRESS,
          abi: erc20ABI,
          functionName: "balanceOf",
          args: [recipientAddress],
        })) as bigint;

        logger.info("G$ Balance after transfer:", {
          address: recipientAddress,
          balance: balanceAfter.toString(),
        });

        return { success: true, txnHash: bundleTxnHash };
      }
    } catch (error) {
      logger.error("Error processing achievement claim:", {
        error: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
        achievementId: request.data?.achievementId,
      });
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "Error processing achievement claim.");
    }
  }
);
