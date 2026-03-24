import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { Address, encodeFunctionData, http } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { celo } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { createViemAccount } from "@privy-io/server-auth/viem";
import { erc20ABI } from "../../utils/abis/erc20";
import { paxAccountV1ABI } from "../../utils/abis/paxAccountV1ABI";
import {
  FUNCTION_RUNTIME_OPTS,
  PRIVY_CLIENT,
  PUBLIC_CLIENT,
  PIMLICO_URL,
  AUTH,
  MIN_DONATION_AMOUNT_GD,
} from "../../utils/config";
import { decryptPrivateKey } from "../../utils/helpers/decryptPrivateKey";

export const donateToGoodCollective = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      logger.info("donateToGoodCollective: request received");
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
        throw new HttpsError(
          "unauthenticated",
          "The function must be called by an authenticated user."
        );
      }

      const userId = request.auth.uid;
      logger.info("donateToGoodCollective: auth verified", { userId });
      const userRecord = await AUTH.getUser(userId);
      if (userRecord.disabled) {
        throw new HttpsError("permission-denied", "This user is disabled.");
      }

      const {
        paxAccountAddress,
        amountDonated,
        currency,
        decimals = 18,
        tokenId,
        donationContract,
        donationMethodId,
        serverWalletId,
        encryptedPrivateKey,
        sessionKey,
        eoWalletAddress,
      } = request.data as {
        paxAccountAddress: string;
        amountDonated: string;
        currency: string;
        decimals?: number;
        tokenId: number;
        donationContract: string;
        donationMethodId?: number;
        serverWalletId?: string;
        encryptedPrivateKey?: string;
        sessionKey?: string;
        eoWalletAddress?: string;
      };

      if (!paxAccountAddress || !amountDonated || !currency || !donationContract) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required donation parameters."
        );
      }
      const isV2 = !!encryptedPrivateKey && !!sessionKey && !!eoWalletAddress;
      const isV1 = !isV2 && !!serverWalletId;
      if (!isV1 && !isV2) {
        throw new HttpsError(
          "invalid-argument",
          "Provide serverWalletId for V1, or encryptedPrivateKey+sessionKey+eoWalletAddress for V2."
        );
      }
      logger.info("donateToGoodCollective: request payload validated", {
        userId,
        paxAccountAddress,
        donationContract,
        currency,
        tokenId,
        isV1,
        isV2,
      });
      if (tokenId !== 1) {
        throw new HttpsError("invalid-argument", "Donations only support G$.");
      }

      const amountFloat = parseFloat(amountDonated);
      if (Number.isNaN(amountFloat) || amountFloat < MIN_DONATION_AMOUNT_GD) {
        throw new HttpsError(
          "invalid-argument",
          `Minimum donation amount is ${MIN_DONATION_AMOUNT_GD} G$.`
        );
      }
      const multiplier = BigInt(10) ** BigInt(decimals);
      const amountInWei = BigInt(Math.floor(amountFloat * Number(multiplier)));
      logger.info("donateToGoodCollective: donation amount validated", {
        userId,
        amountDonated,
        amountInWei: amountInWei.toString(),
        decimals,
      });

      let smartAccount: Awaited<ReturnType<typeof toSimpleSmartAccount>>;
      if (isV1) {
        logger.info("donateToGoodCollective: resolving V1 smart account", {
          userId,
          serverWalletId,
        });
        const wallet = await PRIVY_CLIENT.walletApi.getWallet({
          id: serverWalletId!,
        });
        if (!wallet) {
          throw new HttpsError("not-found", "Server wallet not found.");
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
        logger.info("donateToGoodCollective: resolving V2 smart account", {
          userId,
          eoWalletAddress,
        });
        let privateKeyHex = decryptPrivateKey(encryptedPrivateKey!, sessionKey!);
        if (!privateKeyHex.startsWith("0x")) {
          privateKeyHex = "0x" + privateKeyHex;
        }
        const eoaAccount = privateKeyToAccount(privateKeyHex as `0x${string}`);
        if (eoaAccount.address.toLowerCase() !== eoWalletAddress!.toLowerCase()) {
          throw new HttpsError(
            "invalid-argument",
            "Private key does not match provided EOA address."
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
      }
      logger.info("donateToGoodCollective: smart account resolved", {
        userId,
        smartAccountAddress: smartAccount.address,
      });

      const smartAccountClient = createSmartAccountClient({
        account: smartAccount,
        chain: celo,
        bundlerTransport: http(PIMLICO_URL),
        paymaster: PIMLICO_CLIENT,
        userOperation: {
          estimateFeesPerGas: async () =>
            (await PIMLICO_CLIENT.getUserOperationGasPrice()).fast,
        },
      });

      let userOpTxnHash: `0x${string}`;
      const emptyTransferAndCallData: `0x${string}` = "0x";
      if (isV1) {
        logger.info("donateToGoodCollective: preparing V1 calls", { userId });
        const existingPaymentMethods = (await PUBLIC_CLIENT.readContract({
          address: paxAccountAddress as Address,
          abi: paxAccountV1ABI,
          functionName: "getPaymentMethods",
        })) as Array<{ id: bigint; paymentAddress: Address }>;

        const normalizedSmartAccountAddress = smartAccount.address.toLowerCase();
        const existingByAddress = existingPaymentMethods.find(
          (m) => m.paymentAddress.toLowerCase() === normalizedSmartAccountAddress
        );

        let resolvedWithdrawalMethodId: number;
        let addPaymentMethodData: `0x${string}` | null = null;

        if (existingByAddress) {
          resolvedWithdrawalMethodId = Number(existingByAddress.id);
        } else {
          const usedIds = new Set(
            existingPaymentMethods.map((m) => Number(m.id))
          );
          const requestedId = Number.isInteger(donationMethodId)
            ? Number(donationMethodId)
            : 0;
          if (requestedId > 0 && !usedIds.has(requestedId)) {
            resolvedWithdrawalMethodId = requestedId;
          } else {
            let nextId = 1;
            while (usedIds.has(nextId)) {
              nextId++;
            }
            resolvedWithdrawalMethodId = nextId;
          }

          addPaymentMethodData = encodeFunctionData({
            abi: paxAccountV1ABI,
            functionName: "addNonPrimaryPaymentMethod",
            args: [BigInt(resolvedWithdrawalMethodId), smartAccount.address],
          });
        }

        const withdrawData = encodeFunctionData({
          abi: paxAccountV1ABI,
          functionName: "withdrawToPaymentMethod",
          args: [
            BigInt(resolvedWithdrawalMethodId),
            amountInWei,
            currency as Address,
          ],
        });
        const transferAndCallData = encodeFunctionData({
          abi: erc20ABI,
          functionName: "transferAndCall",
          args: [
            donationContract as Address,
            amountInWei,
            emptyTransferAndCallData,
          ],
        });

        const calls: Array<{ to: Address; value: bigint; data: `0x${string}` }> =
          [];
        if (addPaymentMethodData) {
          calls.push({
            to: paxAccountAddress as Address,
            value: BigInt(0),
            data: addPaymentMethodData,
          });
        }
        calls.push({
          to: paxAccountAddress as Address,
          value: BigInt(0),
          data: withdrawData,
        });
        calls.push({
          to: currency as Address,
          value: BigInt(0),
          data: transferAndCallData,
        });

        logger.info("donateToGoodCollective: sending V1 user operation", {
          userId,
          callCount: calls.length,
          addedPaymentMethod: !!addPaymentMethodData,
        });
        userOpTxnHash = await smartAccountClient.sendUserOperation({
          calls,
        });
      } else {
        logger.info("donateToGoodCollective: sending V2 user operation", {
          userId,
          callCount: 1,
        });
        const transferData = encodeFunctionData({
          abi: erc20ABI,
          functionName: "transferAndCall",
          args: [
            donationContract as Address,
            amountInWei,
            emptyTransferAndCallData,
          ],
        });
        userOpTxnHash = await smartAccountClient.sendUserOperation({
          calls: [
            {
              to: currency as Address,
              value: BigInt(0),
              data: transferData,
            },
          ],
        });
      }
      logger.info("donateToGoodCollective: user operation submitted", {
        userId,
        userOpTxnHash,
      });

      logger.info("donateToGoodCollective: waiting for user operation receipt", {
        userId,
        userOpTxnHash,
      });
      const userOpReceipt = await smartAccountClient.waitForUserOperationReceipt({
        hash: userOpTxnHash,
      });
      if (!userOpReceipt.success) {
        logger.error("donateToGoodCollective: user operation failed", {
          userId,
          userOpTxnHash,
        });
        throw new HttpsError("internal", "Donation user operation failed.");
      }

      const bundleTxnHash = userOpReceipt.receipt.transactionHash;
      logger.info("Donation submitted successfully", {
        userId,
        paxAccountAddress,
        donationContract,
        amountDonated,
        txnHash: bundleTxnHash,
      });

      return {
        success: true,
        txnHash: bundleTxnHash,
        details: {
          paxAccountAddress,
          donationContract,
          amountDonated,
          amountInWei: amountInWei.toString(),
          currency,
          tokenId,
        },
      };
    } catch (error) {
      logger.error("Error donating to goodcollective", { error });
      let errorMessage = "Unknown error occurred";
      if (error instanceof Error) {
        errorMessage = error.message;
      }
      throw new HttpsError(
        "internal",
        `Failed to donate to goodcollective: ${errorMessage}`
      );
    }
  }
);
