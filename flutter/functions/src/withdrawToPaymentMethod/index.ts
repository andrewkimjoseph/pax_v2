// src/withdrawToPaymentMethod/index.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { Address, encodeFunctionData, http } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { celo } from "viem/chains";
import { createViemAccount } from "@privy-io/server-auth/viem";
import { privateKeyToAccount } from "viem/accounts";

import { paxAccountV1ABI } from "../../utils/abis/paxAccountV1ABI";
import { erc20ABI } from "../../utils/abis/erc20";
import {
  FUNCTION_RUNTIME_OPTS,
  PRIVY_CLIENT,
  PUBLIC_CLIENT,
  PIMLICO_URL,
  AUTH,
} from "../../utils/config";
import { decryptPrivateKey } from "../../utils/helpers/decryptPrivateKey";
import { createWithdrawalRecord } from "../../utils/helpers/createWithdrawal";
import { getReferralTagFromSmartAccount } from "../../utils/helpers/getReferralTagFromSmartAccount";

/**
 * Cloud function to withdraw tokens to a payment method
 */
export const withdrawToPaymentMethod = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      // Ensure the user is authenticated
      const { createSmartAccountClient } = await import("permissionless");
      const { toSimpleSmartAccount } = await import("permissionless/accounts");
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
      if (!request.auth) {
        logger.error("Unauthenticated request to withdrawToPaymentMethod", {
          requestAuth: request.auth,
        });
        throw new HttpsError(
          "unauthenticated",
          "The function must be called by an authenticated user."
        );
      }

      const userId = request.auth.uid;

      // Check user's banned status immediately after authentication
      const userRecord = await AUTH.getUser(userId);
      if (userRecord.disabled) {
        throw new HttpsError("permission-denied", "This user is disabled.");
      }

      const {
        serverWalletId,
        paxAccountAddress,
        paymentMethodId, // V1: contract payment method ID (predefinedId - 1)
        withdrawalPaymentMethodId,
        amountRequested,
        currency,
        decimals = 18,
        tokenId,
        // V2 path: ephemeral key + destination address (serverWalletId NOT required)
        encryptedPrivateKey,
        sessionKey,
        eoWalletAddress,
        paymentMethodAddress, // V2: destination wallet address for ERC20 transfer
      } = request.data as {
        serverWalletId?: string;
        paxAccountAddress: string;
        paymentMethodId?: number;
        withdrawalPaymentMethodId: string;
        amountRequested: string;
        currency: string;
        decimals?: number;
        tokenId: number;
        encryptedPrivateKey?: string;
        sessionKey?: string;
        eoWalletAddress?: string;
        paymentMethodAddress?: string;
      };

      const isV2 =
        !!encryptedPrivateKey &&
        !!sessionKey &&
        !!eoWalletAddress &&
        !!paymentMethodAddress;
      const isV1 = !isV2 && !!serverWalletId;
      const logPrefix = isV2 ? "[V2]" : "[V1]";

      if (!paxAccountAddress) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: paxAccountAddress"
        );
      }
      if (!amountRequested) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: amountRequested"
        );
      }
      if (!currency) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: currency"
        );
      }
      if (tokenId === undefined) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: tokenId"
        );
      }
      if (!withdrawalPaymentMethodId) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: withdrawalPaymentMethodId"
        );
      }
      if (!isV1 && !isV2) {
        logger.error(
          "Either serverWalletId (V1) or encryptedPrivateKey+sessionKey+eoWalletAddress+paymentMethodAddress (V2) required",
          {
            hasServerWalletId: !!serverWalletId,
            hasV2Params:
              !!encryptedPrivateKey &&
              !!sessionKey &&
              !!eoWalletAddress &&
              !!paymentMethodAddress,
          }
        );
        throw new HttpsError(
          "invalid-argument",
          "Provide serverWalletId for V1, or encryptedPrivateKey, sessionKey, eoWalletAddress, and paymentMethodAddress for V2."
        );
      }
      if (isV1 && paymentMethodId === undefined) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: paymentMethodId for V1 withdraw"
        );
      }

      // Convert the decimal amount to wei (smallest unit)
      // Example: 0.5 tokens with 18 decimals = 0.5 * 10^18 = 500000000000000000 wei
      let amountInWei: bigint;
      try {
        // Parse the amount as a floating point number
        const amountFloat = parseFloat(amountRequested);

        // Convert to wei by multiplying by 10^decimals
        const multiplier = BigInt(10) ** BigInt(decimals);
        amountInWei = BigInt(Math.floor(amountFloat * Number(multiplier)));

        // For high precision, we could use a library like bignumber.js instead
        // This approach may have precision limitations for very small numbers
      } catch (error) {
        throw new HttpsError(
          "invalid-argument",
          "Invalid amountRequested format. Please provide a valid number."
        );
      }

      logger.info(`${logPrefix} Withdrawing tokens to payment method`, {
        userId,
        paxAccountAddress,
        paymentMethodId,
        amountRequested,
        amountInWei: amountInWei.toString(),
        currency,
        serverWalletId,
        tokenId,
        isV2,
      });

      let smartAccount: Awaited<ReturnType<typeof toSimpleSmartAccount>>;

      if (isV1) {
        const wallet = await PRIVY_CLIENT.walletApi.getWallet({
          id: serverWalletId!,
        });
        if (!wallet) {
          throw new HttpsError(
            "not-found",
            "Server wallet not found with the provided ID"
          );
        }
        const serverWalletAccount = await createViemAccount({
          walletId: wallet.id,
          address: wallet.address as Address,
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
        // V2: build smart account from decrypted EOA key
        let privateKeyHex: string;
        try {
          privateKeyHex = decryptPrivateKey(encryptedPrivateKey!, sessionKey!);
          if (!privateKeyHex.startsWith("0x")) {
            privateKeyHex = "0x" + privateKeyHex;
          }
        } catch (error) {
          logger.error("[V2] Failed to decrypt private key (V2 withdraw)", { error });
          throw new HttpsError(
            "invalid-argument",
            "Failed to decrypt private key. Invalid session key or corrupted data."
          );
        }
        const eoaAccount = privateKeyToAccount(privateKeyHex as `0x${string}`);
        if (
          eoaAccount.address.toLowerCase() !== eoWalletAddress!.toLowerCase()
        ) {
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

      logger.info(`${logPrefix} Using Smart Account`, {
        address: smartAccount.address,
      });

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

      let userOpTxnHash: `0x${string}`;

      if (isV1) {
        const withdrawData = encodeFunctionData({
          abi: paxAccountV1ABI,
          functionName: "withdrawToPaymentMethod",
          args: [BigInt(paymentMethodId!), amountInWei, currency as Address],
        });
        userOpTxnHash = await smartAccountClient.sendUserOperation({
          calls: [
            {
              to: paxAccountAddress as Address,
              value: BigInt(0),
              data: (withdrawData + referralTag) as Address,
            },
          ],
        });
      } else {
        const transferData = encodeFunctionData({
          abi: erc20ABI,
          functionName: "transfer",
          args: [paymentMethodAddress! as Address, amountInWei],
        });
        userOpTxnHash = await smartAccountClient.sendUserOperation({
          calls: [
            {
              to: currency as Address,
              value: BigInt(0),
              data: (transferData + referralTag) as Address,
            },
          ],
        });
      }

      logger.info(`${logPrefix} User operation submitted`, { userOpTxnHash });

      // Wait for user operation receipt
      const userOpReceipt =
        await smartAccountClient.waitForUserOperationReceipt({
          hash: userOpTxnHash,
        });

      if (!userOpReceipt.success) {
        logger.error(`${logPrefix} User operation failed in withdrawToPaymentMethod`, {
          userOpReceipt,
        });
        throw new HttpsError("internal", "User operation failed");
      }

      // const txnHash = userOpReceipt.userOpHash;
      // logger.info("Transaction confirmed", { txnHash });

      const bundleTxnHash = userOpReceipt.receipt.transactionHash;
      logger.info(`${logPrefix} Bundle transaction confirmed`, { bundleTxnHash });

      // Create withdrawal record
      const withdrawalId = await createWithdrawalRecord({
        participantId: userId,
        paymentMethodId: withdrawalPaymentMethodId, // Use the string ID for the withdrawal record
        amountRequested: parseFloat(amountRequested),
        rewardCurrencyId: tokenId,
        txnHash: bundleTxnHash,
      }, isV2 ? "V2" : "V1");

      // Return the transaction hash and details
      return {
        success: true,
        bundleTxnHash,
        txnHash: bundleTxnHash,
        withdrawalId,
        details: {
          paxAccountAddress,
          paymentMethodId: paymentMethodId ?? 0,
          amountRequested,
          amountInWei: amountInWei.toString(),
          currency,
          tokenId,
        },
      };
    } catch (error) {
      logger.error("Error withdrawing tokens", { error });

      let errorMessage = "Unknown error occurred";
      if (error instanceof Error) {
        errorMessage = error.message;
      }

      throw new HttpsError(
        "internal",
        `Failed to withdraw tokens: ${errorMessage}`
      );
    }
  }
);
