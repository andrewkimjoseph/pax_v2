import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { Address, encodeFunctionData, parseUnits } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { createViemAccount } from "@privy-io/server-auth/viem";
import { privateKeyToAccount } from "viem/accounts";
import { canvassingRewarderABI } from "../../utils/abis/canvassingRewarder";
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
  createReferralRewardClaimSignaturePackageCanvassing,
  createReferralRewardWithDonationSignaturePackageCanvassing,
  generateRandomNonce,
} from "../../utils/helpers/rewardingSignature";
import { submitSponsoredRewarderCall } from "../../utils/helpers/submitSponsoredRewarderCall";
import { getTokenConfigForCurrencyId } from "../../utils/helpers/tokenConfig";
import { assertRecipientIsUserWithdrawalMethod } from "../../utils/helpers/validateClaimRecipientAddress";
import type { ToSimpleSmartAccountReturnType } from "permissionless/accounts";

function isHttpsError(e: unknown): e is HttpsError {
  return (
    typeof e === "object" &&
    e !== null &&
    "code" in e &&
    typeof (e as HttpsError).code === "string"
  );
}

interface ProcessReferralClaimRequest {
  referralId: string;
  serverWalletId?: string;
  encryptedPrivateKey?: string;
  sessionKey?: string;
  eoWalletAddress?: string;
  /** Direct-to-EOA payout; must match a payment_methods wallet for the referrer. */
  recipientAddress?: string;
  donationContractAddress?: string;
  donationBasisPoints?: number;
}

export const processReferralClaim = onCall(
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
        referralId,
        serverWalletId,
        encryptedPrivateKey,
        sessionKey,
        eoWalletAddress,
        recipientAddress: recipientAddressFromClient,
        donationContractAddress,
        donationBasisPoints,
      } = request.data as ProcessReferralClaimRequest;

      if (!referralId) {
        throw new HttpsError(
          "invalid-argument",
          "Missing referralId parameter."
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

      const referralDoc = await firestore
        .collection("referrals")
        .doc(referralId)
        .get();

      if (!referralDoc.exists) {
        throw new HttpsError("not-found", "Referral not found");
      }

      const referralData = referralDoc.data();
      if (!referralData) {
        throw new HttpsError("not-found", "Referral data is empty");
      }

      const {
        referredParticipantId,
        referringParticipantId,
        amountReceived,
        txnHash,
      }: {
        referredParticipantId?: string;
        referringParticipantId?: string;
        amountReceived?: number;
        txnHash?: string | null;
      } = referralData;

      if (!referredParticipantId) {
        throw new HttpsError(
          "invalid-argument",
          "Referral missing required field: referredParticipantId"
        );
      }

      if (!referringParticipantId) {
        throw new HttpsError(
          "invalid-argument",
          "Referral missing required field: referringParticipantId"
        );
      }

      if (txnHash) {
        throw new HttpsError(
          "already-exists",
          "Referral reward has already been claimed."
        );
      }

      if (userId !== referringParticipantId) {
        logger.warn("Referral claim attempted by non-referrer", {
          referralId,
          callerUserId: userId,
          referringParticipantId,
          referredParticipantId,
        });
        throw new HttpsError(
          "permission-denied",
          "Only the referring participant may claim this referral reward."
        );
      }

      if (!amountReceived || amountReceived <= 0) {
        throw new HttpsError(
          "failed-precondition",
          "Referral has no configured reward amount."
        );
      }

      // Ensure the referred participant has a pax_wallets record with an eoAddress,
      // and that the eoAddress we use for the claim matches that record.
      const paxWalletSnapshot = await firestore
        .collection("pax_wallets")
        .where("participantId", "==", referredParticipantId)
        .limit(1)
        .get();

      if (paxWalletSnapshot.empty) {
        throw new HttpsError(
          "failed-precondition",
          "Pax V2 wallet not found for referred participant"
        );
      }

      const paxWalletData = paxWalletSnapshot.docs[0].data() as {
        eoAddress?: string;
        [key: string]: unknown;
      };
      const referredEoAddress = paxWalletData.eoAddress as string | undefined;

      if (!referredEoAddress) {
        throw new HttpsError(
          "failed-precondition",
          "Pax V2 wallet missing eoAddress for referred participant"
        );
      }

      const participantPaxAccountDoc = await firestore
        .collection("pax_accounts")
        .doc(referringParticipantId)
        .get(); 
      if (!participantPaxAccountDoc.exists) {
        throw new HttpsError(
          "not-found",
          "PaxAccount (V2) not found for referring participant"
        );
      }

      const participantPaxAccountData = participantPaxAccountDoc.data();
      const smartAccountWalletAddress = participantPaxAccountData
        ?.smartAccountWalletAddress as string | undefined;
      const contractAddress = participantPaxAccountData?.contractAddress as
        | string
        | undefined;

      let paxAccountPayoutAddress: Address;

      const { toSimpleSmartAccount } = await import("permissionless/accounts");
      const nonce = generateRandomNonce();

      let eoAddress: Address;

      let smartAccount: ToSimpleSmartAccountReturnType;
      let logPrefix: string;

      if (isV1) {
        logPrefix = "[V1][Referral]";
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
        paxAccountPayoutAddress = smartAccount.address as Address;
        const expectedSmartAccountAddress =
          smartAccountWalletAddress || contractAddress;
        if (expectedSmartAccountAddress) {
          if (
            smartAccount.address.toLowerCase() !==
            expectedSmartAccountAddress.toLowerCase()
          ) {
            logger.error(
              `${logPrefix} Smart account mismatch vs PaxAccount stored address`,
              {
                derived: smartAccount.address,
                smartAccountWalletAddress,
                contractAddress,
              }
            );
            throw new HttpsError(
              "failed-precondition",
              "serverWalletId does not match PaxAccount stored smart account / contract address."
            );
          }
        }
        eoAddress = serverWallet.address as Address;
      } else {
        logPrefix = "[V2][Referral]";
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
          logger.error("[V2][Referral] Decrypt failed", { error });
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

      let recipientAddress: Address;
      if (
        recipientAddressFromClient &&
        recipientAddressFromClient.trim() !== ""
      ) {
        await assertRecipientIsUserWithdrawalMethod(
          referringParticipantId,
          recipientAddressFromClient
        );
        recipientAddress = recipientAddressFromClient as Address;
      } else {
        recipientAddress = isV1
          ? ((contractAddress as Address) || smartAaAddress)
          : smartAaAddress;
      }

      const hasDonationSplit =
        !!donationContractAddress &&
        donationContractAddress.trim() !== "" &&
        Number.isInteger(donationBasisPoints) &&
        Number(donationBasisPoints) > 0 &&
        Number(donationBasisPoints) <= 10000;

      // Referrals are currently paid in the primary reward currency (token id 1).
      const { tokenAddress, decimals } = getTokenConfigForCurrencyId(1);
      const amountWei = parseUnits(String(amountReceived), decimals);

      const signaturePackage = hasDonationSplit
        ? await createReferralRewardWithDonationSignaturePackageCanvassing(
            CANVASSING_REWARDER_PROXY_ADDRESS,
            eoAddress,
            referredEoAddress as Address,
            smartAaAddress,
            recipientAddress,
            donationContractAddress as Address,
            referralId,
            tokenAddress,
            amountWei,
            BigInt(Number(donationBasisPoints)),
            nonce
          )
        : await createReferralRewardClaimSignaturePackageCanvassing(
            CANVASSING_REWARDER_PROXY_ADDRESS,
            eoAddress,
            referredEoAddress as Address,
            smartAaAddress,
            recipientAddress,
            referralId,
            tokenAddress,
            amountWei,
            nonce
          );

      if (!signaturePackage.isValid) {
        throw new HttpsError("internal", "Signature validation failed");
      }

      const rewardClaimData = hasDonationSplit
        ? encodeFunctionData({
            abi: canvassingRewarderABI,
            functionName: "claimReferralRewardWithDonation",
            args: [
              eoAddress,
              referredEoAddress as Address,
              smartAaAddress,
              recipientAddress,
              donationContractAddress as Address,
              referralId,
              tokenAddress,
              amountWei,
              BigInt(Number(donationBasisPoints)),
              nonce,
              signaturePackage.signature,
            ],
          })
        : encodeFunctionData({
            abi: canvassingRewarderABI,
            functionName: "claimReferralReward",
            args: [
              eoAddress,
              referredEoAddress as Address,
              smartAaAddress,
              recipientAddress,
              referralId,
              tokenAddress,
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

      const now = new Date();
      await referralDoc.ref.update({
        txnHash: bundleTxnHash,
        timeRewarded: now,
        timeUpdated: now,
      });

      return {
        success: true,
        participantProxy: smartAaAddress,
        paxAccountContractAddress: recipientAddress,
        referralId,
        txnHash: bundleTxnHash,
        amount: amountReceived,
      };
    } catch (error) {
      if (isHttpsError(error)) throw error;
      logger.error("Referral reward process failed", { error });
      throw new HttpsError(
        "internal",
        `Failed to process referral claim: ${
          error instanceof Error ? error.message : "Unknown error"
        }`
      );
    }
  }
);

