// src/addNonPrimaryWithdrawalMethodToPaxAccountV1Proxy/index.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { Address, encodeFunctionData } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { createViemAccount } from "@privy-io/server-auth/viem";
import {
  FUNCTION_RUNTIME_OPTS,
  PRIVY_CLIENT,
  PUBLIC_CLIENT,
  AUTH,
} from "../../utils/config";
import { paxAccountV1ABI } from "../../utils/abis/paxAccountV1ABI";
import { sendPrivySponsoredUserOp } from "../../utils/celina/sendAaV1Privy";
// Initialize clients

/**
 * Cloud function to add a non-primary payment method to an existing PaxAccount proxy contract
 */
export const addNonPrimaryWithdrawalMethodToPaxAccountV1Proxy = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      const { toSimpleSmartAccount } = await import("permissionless/accounts");

      // Ensure the user is authenticated
      if (!request.auth) {
        logger.error(
          "[V1] Unauthenticated request to addNonPrimaryWithdrawalMethodToPaxAccountV1Proxy",
          {
            requestAuth: request.auth,
          }
        );
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
        walletAddress,
        _paymentMethodId,
        serverWalletId,
        contractAddress,
      } = request.data as {
        walletAddress: string;
        _paymentMethodId: number;
        serverWalletId: string;
        contractAddress: string;
      };

      if (!_paymentMethodId || _paymentMethodId === 0) {
        logger.error(
          "[V1] Invalid payment method ID in addNonPrimaryWithdrawalMethodToPaxAccountV1Proxy",
          { _paymentMethodId }
        );
        throw new HttpsError(
          "invalid-argument",
          "Payment method ID must be provided and cannot be 0 (reserved for primary)"
        );
      }

      if (!walletAddress) {
        logger.error(
          "[V1] Missing required parameter: paymentMethodAddress in addNonPrimaryWithdrawalMethodToPaxAccountV1Proxy",
          { walletAddress }
        );
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: paymentMethodAddress"
        );
      }

      if (!serverWalletId) {
        logger.error(
          "[V1] Missing required parameter: serverWalletId in addNonPrimaryWithdrawalMethodToPaxAccountV1Proxy",
          { serverWalletId }
        );
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: serverWalletId"
        );
      }

      if (!contractAddress) {
        logger.error(
          "[V1] Missing required parameter: contractAddress in addNonPrimaryWithdrawalMethodToPaxAccountV1Proxy",
          { contractAddress }
        );
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: contractAddress"
        );
      }

      logger.info("[V1] Adding non-primary payment method to PaxAccount", {
        userId,
        _paymentMethodId,
        walletAddress,
        serverWalletId,
        contractAddress,
      });

      // Get the server wallet from Privy
      const wallet = await PRIVY_CLIENT.walletApi.getWallet({
        id: serverWalletId,
      });

      if (!wallet) {
        logger.error(
          "[V1] Server wallet not found with the provided ID in addNonPrimaryWithdrawalMethodToPaxAccountV1Proxy",
          { serverWalletId }
        );
        throw new HttpsError(
          "not-found",
          "Server wallet not found with the provided ID"
        );
      }

      // Create viem account from Privy wallet
      const serverWalletAccount = await createViemAccount({
        walletId: wallet.id,
        address: wallet.address as Address,
        privy: PRIVY_CLIENT,
      });

      // Create the Simple smart account
      const smartAccount = await toSimpleSmartAccount({
        client: PUBLIC_CLIENT,
        owner: serverWalletAccount,
        entryPoint: {
          address: entryPoint07Address,
          version: "0.7",
        },
      });

      logger.info("[V1] Using Smart Account", {
        address: smartAccount.address,
      });

      const addNonPrimaryPaymentMethodData = encodeFunctionData({
        abi: paxAccountV1ABI,
        functionName: "addNonPrimaryPaymentMethod",
        args: [BigInt(_paymentMethodId), walletAddress as Address],
      });

      const { bundleTxnHash: txnHash } = await sendPrivySponsoredUserOp({
        smartAccount,
        calls: [
          {
            to: contractAddress as Address,
            value: BigInt(0),
            data: addNonPrimaryPaymentMethodData,
          },
        ],
        logPrefix: "[V1]",
      });

      logger.info("[V1] Payment method addition transaction confirmed", { txnHash });

      return {
        txnHash,
      };
    } catch (error) {
      logger.error("[V1] Error adding non-primary payment method to PaxAccount", {
        error,
      });

      let errorMessage = "Unknown error occurred";
      if (error instanceof Error) {
        errorMessage = error.message;
      }

      throw new HttpsError(
        "internal",
        `Failed to add payment method: ${errorMessage}`
      );
    }
  }
);
