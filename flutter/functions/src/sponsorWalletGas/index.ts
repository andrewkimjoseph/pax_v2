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
  CANVASSING_GAS_SPONSOR_ADDRESS,
  CANVASSING_WALLET_REGISTRY_ADDRESS,
  DB,
} from "../../utils/config";
import { canvassingGasSponsorABI } from "../../utils/abis/new/canvassingGasSponsor";
import { canvassingWalletRegistryABI } from "../../utils/abis/new/canvassingWalletRegistry";

/** Default CELO amount to sponsor per wallet (in ether). */
const DEFAULT_SPONSOR_AMOUNT_CELO = "0.01";

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
        logger.error("Unauthenticated request to sponsorWalletGas");
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
          "V1 user attempted to call sponsorWalletGas (serverWalletId present)",
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
        !CANVASSING_GAS_SPONSOR_ADDRESS ||
        CANVASSING_GAS_SPONSOR_ADDRESS === "0x"
      ) {
        logger.error("CANVASSING_GAS_SPONSOR_ADDRESS not configured");
        throw new HttpsError(
          "failed-precondition",
          "Gas sponsorship not configured."
        );
      }

      const eoAddress = eoWalletAddress as Address;

      const isLogged = (await PUBLIC_CLIENT.readContract({
        address: CANVASSING_WALLET_REGISTRY_ADDRESS,
        abi: canvassingWalletRegistryABI,
        functionName: "isWalletLogged",
        args: [eoAddress],
      })) as boolean;

      if (!isLogged) {
        logger.error("Wallet not in registry, cannot sponsor", {
          eoWalletAddress,
          userId,
        });
        throw new HttpsError(
          "failed-precondition",
          "Wallet must be registered in the wallet registry before gas can be sponsored."
        );
      }

      const amountWei = parseEther(DEFAULT_SPONSOR_AMOUNT_CELO);

      logger.info("Sponsoring wallet gas", {
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
        to: CANVASSING_GAS_SPONSOR_ADDRESS,
        data,
      });

      logger.info("sponsorWalletGas tx submitted", {
        txHash,
        userId,
        eoWalletAddress,
      });

      const receipt = await PUBLIC_CLIENT.waitForTransactionReceipt({
        hash: txHash,
      });

      logger.info("sponsorWalletGas tx confirmed", {
        blockNumber: receipt.blockNumber,
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
      logger.error("sponsorWalletGas error:", error);
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
