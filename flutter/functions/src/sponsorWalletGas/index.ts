import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import {
  Address,
  createWalletClient,
  http,
  encodeFunctionData,
  parseEther,
} from "viem";
import { celo } from "viem/chains";
import {
  PAX_MASTER_PRIVATE_KEY_ACCOUNT,
  FUNCTION_RUNTIME_OPTS,
  PUBLIC_CLIENT,
  DRPC_URL,
  AUTH,
  CANVASSING_GAS_SPONSOR_PROXY_ADDRESS,
  CANVASSING_WALLET_REGISTRY_PROXY_ADDRESS,
  DB,
  DEFAULT_SPONSOR_AMOUNT_CELO,
} from "../../utils/config";
import { canvassingGasSponsorABI } from "../../utils/abis/canvassingGasSponsor";
import { canvassingWalletRegistryABI } from "../../utils/abis/canvassingWalletRegistry";

/**
 * Callable to sponsor gas for a registered wallet.
 * Trigger only when the user completes face verification.
 * The wallet must already be logged in CanvassingWalletRegistry.
 */
export const sponsorWalletGas = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      if (!request.auth) {
        logger.error("[V2] Unauthenticated request to sponsorWalletGas");
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

      // Restrict gas sponsorship to V2 users only (no server wallet)
      const firestore = DB();
      const paxAccountDoc = await firestore
        .collection("pax_accounts")
        .doc(userId)
        .get();

      const paxAccountData = paxAccountDoc.exists ? paxAccountDoc.data() : null;
      const serverWalletId = paxAccountData?.serverWalletId as
        | string
        | undefined;

      if (serverWalletId) {
        logger.error(
          "[V2] V1 user attempted to call sponsorWalletGas (serverWalletId present)",
          { userId, serverWalletId }
        );
        throw new HttpsError(
          "failed-precondition",
          "Gas sponsorship via CanvassingGasSponsor is only available for V2 wallets."
        );
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

      if (
        !CANVASSING_GAS_SPONSOR_PROXY_ADDRESS ||
        CANVASSING_GAS_SPONSOR_PROXY_ADDRESS === "0x"
      ) {
        logger.error("[V2] CANVASSING_GAS_SPONSOR_PROXY_ADDRESS not configured");
        throw new HttpsError(
          "failed-precondition",
          "Gas sponsorship not configured."
        );
      }

      const eoAddress = eoWalletAddress as Address;

      const isLogged = (await PUBLIC_CLIENT.readContract({
        address: CANVASSING_WALLET_REGISTRY_PROXY_ADDRESS,
        abi: canvassingWalletRegistryABI,
        functionName: "isWalletLogged",
        args: [eoAddress],
      })) as boolean;

      if (!isLogged) {
        logger.error("[V2] Wallet not in registry, cannot sponsor", {
          eoWalletAddress,
          userId,
        });
        throw new HttpsError(
          "failed-precondition",
          "Wallet must be registered in the wallet registry before gas can be sponsored."
        );
      }

      const amountWei = parseEther(DEFAULT_SPONSOR_AMOUNT_CELO);
      const minBalanceThresholdWei = amountWei / BigInt(2);

      const currentBalanceWei = await PUBLIC_CLIENT.getBalance({
        address: eoAddress,
      });
      if (currentBalanceWei >= minBalanceThresholdWei) {
        logger.info("[V2] Wallet has sufficient gas, skipping sponsorship", {
          eoWalletAddress,
          userId,
          currentBalanceWei: currentBalanceWei.toString(),
          minBalanceThresholdWei: minBalanceThresholdWei.toString(),
        });
        return {
          skipped: true,
          reason: "balance_sufficient",
          currentBalanceWei: currentBalanceWei.toString(),
          minBalanceThresholdWei: minBalanceThresholdWei.toString(),
          amountWei: amountWei.toString(),
          timestamp: new Date().toISOString(),
        };
      }

      logger.info("[V2] Sponsoring wallet gas", {
        eoWalletAddress,
        userId,
        amountWei: amountWei.toString(),
      });

      const walletClient = createWalletClient({
        account: PAX_MASTER_PRIVATE_KEY_ACCOUNT,
        chain: celo,
        transport: http(DRPC_URL),
      });

      const data = encodeFunctionData({
        abi: canvassingGasSponsorABI,
        functionName: "sponsorWallet",
        args: [eoAddress, amountWei],
      });

      const txHash = await walletClient.sendTransaction({
        to: CANVASSING_GAS_SPONSOR_PROXY_ADDRESS,
        data,
      });

      logger.info("[V2] sponsorWalletGas tx submitted", {
        txHash,
        userId,
        eoWalletAddress,
      });

      const receipt = await PUBLIC_CLIENT.waitForTransactionReceipt({
        hash: txHash,
      });

      logger.info("[V2] sponsorWalletGas tx confirmed", {
        blockNumber: receipt.blockNumber.toString(),
        userId,
        eoWalletAddress,
      });

      return {
        txnHash: txHash,
        amountWei: amountWei.toString(),
        timestamp: new Date().toISOString(),
        blockNumber: receipt.blockNumber.toString(),
      };
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      const stack = error instanceof Error ? error.stack : undefined;
      logger.error("[V2] sponsorWalletGas error:", message);
      if (stack) logger.error("[V2] sponsorWalletGas error stack:", stack);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        `Failed to sponsor wallet gas: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }
);
