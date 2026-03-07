import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FUNCTION_RUNTIME_OPTS, AUTH } from "../../utils/config";
import { fetchEtherscanTxList } from "../../utils/helpers/etherscan";

interface GetWalletTransactionsParams {
  address: string;
  page?: number;
  offset?: number;
}

export const getWalletTransactions = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError(
          "unauthenticated",
          "The function must be called by an authenticated user."
        );
      }

      const userRecord = await AUTH.getUser(request.auth.uid);
      if (userRecord.disabled) {
        throw new HttpsError("permission-denied", "This user is disabled.");
      }

      const { address, page = 1, offset = 20 } =
        request.data as GetWalletTransactionsParams;

      if (!address || typeof address !== "string") {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameter: address"
        );
      }

      const { status, message, result } = await fetchEtherscanTxList({
        address,
        page,
        offset,
      });

      return { status, message, result };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("getWalletTransactions error:", error);
      throw new HttpsError(
        "internal",
        `Failed to fetch transactions: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }
);
