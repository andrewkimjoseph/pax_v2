import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { Address, encodeFunctionData, parseUnits } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { privateKeyToAccount } from "viem/accounts";
import { createViemAccount } from "@privy-io/server-auth/viem";
import {
  FUNCTION_RUNTIME_OPTS,
  PUBLIC_CLIENT,
  DB,
  AUTH,
  CANVASSING_REWARDER_PROXY_ADDRESS,
  PRIVY_CLIENT,
} from "../../utils/config";
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
        amountEarned === undefined ||
        tasksCompleted === undefined
      ) {
        logger.error("Missing required parameters in processAchievementClaim", {
          achievementId,
          amountEarned,
          tasksCompleted,
        });
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameters: achievementId, amountEarned, tasksCompleted."
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

      // Achievements are paid in the primary reward currency (token id 1).
      const { tokenAddress, decimals } = getTokenConfigForCurrencyId(1);
      const hasDonationSplit =
        !!donationContractAddress &&
        donationContractAddress.trim() !== "" &&
        Number.isInteger(donationBasisPoints) &&
        Number(donationBasisPoints) > 0 &&
        Number(donationBasisPoints) <= 10000;

      const isV2 = !!eoWalletAddress && !!encryptedPrivateKey && !!sessionKey;

      const paxAccountDoc = await firestore
        .collection("pax_accounts")
        .doc(userId)
        .get();
      if (!paxAccountDoc.exists) {
        throw new HttpsError("not-found", "PaxAccount record not found.");
      }
      const paxData = paxAccountDoc.data();
      const contractAddressFromPax = paxData?.contractAddress as
        | string
        | undefined;
      const smartAccountWalletAddressFromPax = paxData?.smartAccountWalletAddress as
        | string
        | undefined;

      if (isV2) {
        if (
          !smartAccountWalletAddressFromPax ||
          smartAccountWalletAddressFromPax.trim() === ""
        ) {
          throw new HttpsError(
            "failed-precondition",
            "V2 PaxAccount missing smartAccountWalletAddress."
          );
        }
        const smartAccountContractAddress =
          smartAccountWalletAddressFromPax as Address;

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
            smartAccountWalletAddress: smartAccountContractAddress,
          });
          throw new HttpsError(
            "failed-precondition",
            "Wallet smart account does not match PaxAccount.smartAccountWalletAddress."
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
          recipientAddress = smartAccountContractAddress;
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
        logger.info("[V1] Sponsored CanvassingRewarder achievement claim (Privy)", {
          userId,
          achievementId,
        });

        const serverWalletId = paxData?.serverWalletId as string | undefined;
        const contractAddress = contractAddressFromPax;

        if (!contractAddress || contractAddress.trim() === "") {
          throw new HttpsError(
            "failed-precondition",
            "V1 PaxAccount missing contractAddress (PaxAccountV1 proxy)."
          );
        }

        if (!serverWalletId || serverWalletId.trim() === "") {
          throw new HttpsError(
            "invalid-argument",
            "V1 achievement claim requires PaxAccount.serverWalletId."
          );
        }

        const serverWallet = await PRIVY_CLIENT.walletApi.getWallet({
          id: serverWalletId,
        });
        if (!serverWallet) {
          throw new HttpsError("not-found", "Server wallet not found");
        }

        const { toSimpleSmartAccount } = await import(
          "permissionless/accounts"
        );
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

        const smartAaAddress = smartAccount.address as Address;
        // V1: PaxAccountV1 proxy (contractAddress) != Privy-derived AA; do not compare them.
        const achievementCallerSmartAccount = smartAaAddress;

        const eoAddress = serverWallet.address as Address;

        let recipientAddress: Address;
        if (recipientAddressRaw && recipientAddressRaw.trim() !== "") {
          await assertRecipientIsUserWithdrawalMethod(
            userId,
            recipientAddressRaw
          );
          recipientAddress = recipientAddressRaw as Address;
        } else {
          recipientAddress = contractAddress as Address;
        }

        const amountWei = parseUnits(String(amountEarned), decimals);
        const nonce = generateRandomNonce();

        const signaturePackage = hasDonationSplit
          ? await createAchievementRewardWithDonationSignaturePackageCanvassing(
              CANVASSING_REWARDER_PROXY_ADDRESS,
              eoAddress,
              achievementCallerSmartAccount,
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
              achievementCallerSmartAccount,
              recipientAddress,
              achievementId,
              tokenAddress,
              amountWei,
              nonce
            );

        if (!signaturePackage.isValid) {
          logger.error("[V1] Achievement claim signature validation failed", {
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
                achievementCallerSmartAccount,
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
                achievementCallerSmartAccount,
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
          logPrefix: "[V1]",
        });

        logger.info("[V1] Achievement claim userOp confirmed", {
          bundleTxnHash,
          achievementId,
        });

        await firestore.collection("achievements").doc(achievementId).update({
          txnHash: bundleTxnHash,
          timeClaimed: new Date(),
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
