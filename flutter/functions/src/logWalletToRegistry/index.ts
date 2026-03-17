import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { Address, createWalletClient, http, encodeFunctionData } from "viem";
import { celo } from "viem/chains";
import {
  PAX_MASTER_PRIVATE_KEY_ACCOUNT,
  FUNCTION_RUNTIME_OPTS,
  PUBLIC_CLIENT,
  DRPC_URL,
  AUTH,
  CANVASSING_WALLET_REGISTRY_PROXY_ADDRESS,
} from "../../utils/config";
import { canvassingWalletRegistryABI } from "../../utils/abis/canvassingWalletRegistry";

export const logWalletToRegistry = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      if (!request.auth) {
        logger.error("[V2] Unauthenticated request to logWalletToRegistry");
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

      const { eoWalletAddress } = request.data as {
        eoWalletAddress: string;
      };

      if (!eoWalletAddress) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: eoWalletAddress"
        );
      }

      logger.info(
        `[V2] logWalletToRegistry: logging wallet ${eoWalletAddress} for user ${userId}`
      );

      const walletClient = createWalletClient({
        account: PAX_MASTER_PRIVATE_KEY_ACCOUNT,
        chain: celo,
        transport: http(DRPC_URL),
      });

      const data = encodeFunctionData({
        abi: canvassingWalletRegistryABI,
        functionName: "logWallet",
        args: [eoWalletAddress as Address, userId],
      });

      const txHash = await walletClient.sendTransaction({
        to: CANVASSING_WALLET_REGISTRY_PROXY_ADDRESS,
        data,
      });

      logger.info(
        `[V2] logWalletToRegistry: tx submitted ${txHash} for user ${userId}`
      );

      const receipt = await PUBLIC_CLIENT.waitForTransactionReceipt({
        hash: txHash,
      });

      logger.info(
        `[V2] logWalletToRegistry: tx confirmed in block ${receipt.blockNumber} for user ${userId}`
      );

      return {
        txnHash: txHash,
        timestamp: new Date().toISOString(),
        blockNumber: receipt.blockNumber.toString(),
      };
    } catch (error: any) {
      logger.error("[V2] logWalletToRegistry error:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        `Failed to log wallet to registry: ${error.message || error}`
      );
    }
  }
);
