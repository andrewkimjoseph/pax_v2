import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { Address, encodeFunctionData, http, parseUnits } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { celo } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import {
  FUNCTION_RUNTIME_OPTS,
  PUBLIC_CLIENT,
  DB,
  AUTH,
  CANVASSING_REWARDER_PROXY_ADDRESS,
  PIMLICO_URL,
  PAX_MASTER_PRIVATE_KEY_ACCOUNT,
} from "../../utils/config";
import { erc20ABI } from "../../utils/abis/erc20";
import { decryptPrivateKey } from "../../utils/helpers/decryptPrivateKey";
import {
  createAchievementRewardClaimSignaturePackageCanvassing,
  createAchievementRewardWithDonationSignaturePackageCanvassing,
  generateRandomNonce,
} from "../../utils/helpers/rewardingSignature";
import { canvassingRewarderABI } from "../../utils/abis/canvassingRewarder";
import { submitSponsoredRewarderCall } from "../../utils/helpers/submitSponsoredRewarderCall";
import { getTokenConfigForCurrencyId } from "../../utils/helpers/tokenConfig";
import { assertRecipientIsUserWithdrawalMethod } from "../../utils/helpers/validateClaimRecipientAddress";
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
        recipientAddress: recipientAddressRaw,
        amountEarned,
        tasksCompleted,
        eoWalletAddress,
        encryptedPrivateKey,
        sessionKey,
        donationContractAddress,
        donationBasisPoints,
      } = request.data as {
        achievementId: string;
        paxAccountContractAddress: string;
        recipientAddress?: string;
        amountEarned: number;
        tasksCompleted: number;
        eoWalletAddress?: string;
        encryptedPrivateKey?: string;
        sessionKey?: string;
        donationContractAddress?: string;
        donationBasisPoints?: number;
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
      // Achievements are paid in the primary reward currency (token id 1).
      const { tokenAddress, decimals } = getTokenConfigForCurrencyId(1);
      const hasDonationSplit =
        !!donationContractAddress &&
        donationContractAddress.trim() !== "" &&
        Number.isInteger(donationBasisPoints) &&
        Number(donationBasisPoints) > 0 &&
        Number(donationBasisPoints) <= 10000;

      const isV2 = !!eoWalletAddress && !!encryptedPrivateKey && !!sessionKey;

      if (isV2) {
        if (
          !CANVASSING_REWARDER_PROXY_ADDRESS ||
          CANVASSING_REWARDER_PROXY_ADDRESS === "0x"
        ) {
          logger.error("[V2] CANVASSING_REWARDER_PROXY_ADDRESS not configured");
          throw new HttpsError(
            "failed-precondition",
            "Achievement claim service not configured. Missing CANVASSING_REWARDER_PROXY_ADDRESS."
          );
        }

        let privateKeyHex: string;
        try {
          privateKeyHex = decryptPrivateKey(encryptedPrivateKey, sessionKey);
          if (!privateKeyHex.startsWith("0x")) {
            privateKeyHex = "0x" + privateKeyHex;
          }
        } catch (error) {
          logger.error("[V2] Failed to decrypt private key (achievement claim)", {
            error,
          });
          throw new HttpsError(
            "invalid-argument",
            "Failed to decrypt private key. Invalid session key or corrupted data."
          );
        }
        const eoaAccount = privateKeyToAccount(privateKeyHex as `0x${string}`);
        if (eoaAccount.address.toLowerCase() !== eoWalletAddress.toLowerCase()) {
          logger.error("[V2] EOA address mismatch (achievement claim)", {
            derived: eoaAccount.address,
            provided: eoWalletAddress,
          });
          throw new HttpsError(
            "invalid-argument",
            "Private key does not match provided EOA address"
          );
        }
        const eoAddress = eoWalletAddress as Address;
        privateKeyHex = "";

        const { toSimpleSmartAccount } = await import(
          "permissionless/accounts"
        );
        const smartAccount = await toSimpleSmartAccount({
          client: PUBLIC_CLIENT,
          owner: eoaAccount,
          entryPoint: {
            address: entryPoint07Address,
            version: "0.7",
          },
        });
        if (
          smartAccount.address.toLowerCase() !==
          smartAccountContractAddress.toLowerCase()
        ) {
          logger.error("[V2] Smart account mismatch (achievement claim)", {
            derived: smartAccount.address,
            paxAccountContractAddress: smartAccountContractAddress,
          });
          throw new HttpsError(
            "failed-precondition",
            "Wallet smart account does not match paxAccountContractAddress."
          );
        }

        logger.info("[V2] Sponsored CanvassingRewarder achievement claim", {
          userId,
          achievementId,
          smartAccountContractAddress,
          eoAddress,
        });

        const amountWei = parseUnits(String(amountEarned), decimals);
        const nonce = generateRandomNonce();

        let recipientAddress: Address;
        if (recipientAddressRaw && recipientAddressRaw.trim() !== "") {
          await assertRecipientIsUserWithdrawalMethod(
            userId,
            recipientAddressRaw
          );
          recipientAddress = recipientAddressRaw as Address;
        } else {
          recipientAddress = paxAccountContractAddress as Address;
        }

        const signaturePackage = hasDonationSplit
          ? await createAchievementRewardWithDonationSignaturePackageCanvassing(
              CANVASSING_REWARDER_PROXY_ADDRESS,
              eoAddress,
              smartAccountContractAddress,
              recipientAddress,
              donationContractAddress as Address,
              achievementId,
              tokenAddress,
              amountWei,
              BigInt(Number(donationBasisPoints)),
              nonce
            )
          : await createAchievementRewardClaimSignaturePackageCanvassing(
              CANVASSING_REWARDER_PROXY_ADDRESS,
              eoAddress,
              smartAccountContractAddress,
              recipientAddress,
              achievementId,
              tokenAddress,
              amountWei,
              nonce
            );

        if (!signaturePackage.isValid) {
          logger.error("[V2] Achievement claim signature validation failed", {
            signaturePackage,
          });
          throw new HttpsError("internal", "Signature validation failed");
        }

        const data = hasDonationSplit
          ? encodeFunctionData({
              abi: canvassingRewarderABI,
              functionName: "claimAchievementRewardWithDonation",
              args: [
                eoAddress,
                smartAccountContractAddress,
                recipientAddress,
                donationContractAddress as Address,
                achievementId,
                tokenAddress,
                amountWei,
                BigInt(Number(donationBasisPoints)),
                nonce,
                signaturePackage.signature,
              ],
            })
          : encodeFunctionData({
              abi: canvassingRewarderABI,
              functionName: "claimAchievementReward",
              args: [
                eoAddress,
                smartAccountContractAddress,
                recipientAddress,
                achievementId,
                tokenAddress,
                amountWei,
                nonce,
                signaturePackage.signature,
              ],
            });

        const { bundleTxnHash } = await submitSponsoredRewarderCall({
          smartAccount,
          data,
          logPrefix: "[V2]",
        });

        logger.info("[V2] Achievement claim userOp confirmed", {
          bundleTxnHash,
          achievementId,
        });

        await firestore.collection("achievements").doc(achievementId).update({
          txnHash: bundleTxnHash,
          timeClaimed: new Date(),
        });

        return { success: true, txnHash: bundleTxnHash };
      } else {
        logger.info("[V1] Using V1 Pimlico achievement claim flow", {
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

        let recipientAddress: Address;
        if (recipientAddressRaw && recipientAddressRaw.trim() !== "") {
          await assertRecipientIsUserWithdrawalMethod(
            userId,
            recipientAddressRaw
          );
          recipientAddress = recipientAddressRaw as Address;
        } else {
          recipientAddress = smartAccountContractAddress;
        }

        logger.info("[V1] Preparing V1 achievement claim transaction", {
          recipientAddress,
          amountEarned: amountEarned.toString(),
          rewardTokenAddress: tokenAddress,
        });

        const paxMasterSmartAccount = await toSimpleSmartAccount({
          client: PUBLIC_CLIENT,
          owner: PAX_MASTER_PRIVATE_KEY_ACCOUNT,
          entryPoint: {
            address: entryPoint07Address,
            version: "0.7",
          },
        });

        logger.info("[V1] V1 Smart Account Address:", {
          address: paxMasterSmartAccount.address,
        });

        const balanceBefore = (await PUBLIC_CLIENT.readContract({
          address: tokenAddress,
          abi: erc20ABI,
          functionName: "balanceOf",
          args: [recipientAddress],
        })) as bigint;

        logger.info("[V1] G$ Balance before transfer:", {
          address: recipientAddress,
          balance: balanceBefore.toString(),
        });

        const data = encodeFunctionData({
          abi: erc20ABI,
          functionName: "transfer",
          args: [recipientAddress, parseUnits(amountEarned.toString(), decimals)],
        });

        logger.info("[V1] Encoded V1 achievement claim transaction data");

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

        const userOpTxnHash = await smartAccountClient.sendUserOperation({
          calls: [
            {
              to: tokenAddress,
              data,
            },
          ],
        });

        logger.info("[V1] V1 user operation submitted", { userOpTxnHash });

        const userOpReceipt =
          await smartAccountClient.waitForUserOperationReceipt({
            hash: userOpTxnHash,
          });

        if (!userOpReceipt.success) {
          logger.error("[V1] User operation failed in processAchievementClaim", {
            userOpReceipt,
          });
          throw new HttpsError(
            "internal",
            `User operation failed: ${JSON.stringify(userOpReceipt)}`
          );
        }

        const bundleTxnHash = userOpReceipt.receipt.transactionHash;
        logger.info("[V1] V1 bundle transaction confirmed", { bundleTxnHash });

        await firestore.collection("achievements").doc(achievementId).update({
          txnHash: bundleTxnHash,
          timeClaimed: new Date(),
        });

        const balanceAfter = (await PUBLIC_CLIENT.readContract({
          address: tokenAddress,
          abi: erc20ABI,
          functionName: "balanceOf",
          args: [recipientAddress],
        })) as bigint;

        logger.info("[V1] G$ Balance after transfer:", {
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
