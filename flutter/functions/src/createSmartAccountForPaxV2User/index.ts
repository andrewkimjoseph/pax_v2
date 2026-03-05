import {onCall, HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions/v2";
import {Address, http} from "viem";
import {entryPoint07Address} from "viem/account-abstraction";
import {celo} from "viem/chains";
import {privateKeyToAccount} from "viem/accounts";
import {
  FUNCTION_RUNTIME_OPTS,
  PUBLIC_CLIENT,
  PIMLICO_URL,
} from "../../utils/config";
import {decryptPrivateKey} from "../../utils/helpers/decryptPrivateKey";

export const createSmartAccountForPaxV2User = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      const {createSmartAccountClient} = await import("permissionless");
      const {toSimpleSmartAccount} = await import("permissionless/accounts");
      const {createPimlicoClient} = await import(
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
        logger.error(
          "[V2] Unauthenticated request to createSmartAccountForPaxV2User"
        );
        throw new HttpsError(
          "unauthenticated",
          "The function must be called by an authenticated user."
        );
      }

      const userId = request.auth.uid;

      const {encryptedPrivateKey, eoWalletAddress, sessionKey} =
        request.data as {
          encryptedPrivateKey: string;
          eoWalletAddress: string;
          sessionKey: string;
        };

      if (!encryptedPrivateKey || !eoWalletAddress || !sessionKey) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameters: encryptedPrivateKey, " +
            "eoWalletAddress, sessionKey"
        );
      }

      logger.info("[V2] Creating smart account for v2 user", {
        userId,
        eoWalletAddress,
      });

      let privateKeyHex: string;
      try {
        privateKeyHex = decryptPrivateKey(encryptedPrivateKey, sessionKey);
        if (!privateKeyHex.startsWith("0x")) {
          privateKeyHex = "0x" + privateKeyHex;
        }
      } catch (error) {
        logger.error("[V2] Failed to decrypt private key", {error});
        throw new HttpsError(
          "invalid-argument",
          "Failed to decrypt private key. " +
            "Invalid session key or corrupted data."
        );
      }

      const eoaAccount = privateKeyToAccount(privateKeyHex as Address);

      if (eoaAccount.address.toLowerCase() !== eoWalletAddress.toLowerCase()) {
        logger.error("[V2] EOA address mismatch", {
          derived: eoaAccount.address,
          provided: eoWalletAddress,
        });
        throw new HttpsError(
          "invalid-argument",
          "Private key does not match provided EOA address"
        );
      }

      const smartAccount = await toSimpleSmartAccount({
        client: PUBLIC_CLIENT,
        owner: eoaAccount,
        entryPoint: {
          address: entryPoint07Address,
          version: "0.7",
        },
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

      logger.info("[V2] Smart Account Client created", {
        chain: smartAccountClient.chain?.name,
        accountAddress: smartAccountClient.account?.address,
        entryPointAddress: smartAccountClient.account?.entryPoint?.address,
      });

      logger.info("[V2] Smart Account Address", {
        smartAccountAddress: smartAccount.address,
      });

      privateKeyHex = "";

      return {
        success: true,
        smartAccountAddress: smartAccount.address,
      };
    } catch (error) {
      logger.error("[V2] Error creating smart account", {error});

      let errorMessage = "Unknown error occurred";
      if (error instanceof Error) {
        errorMessage = error.message;
      }

      throw new HttpsError(
        "internal",
        `Failed to create smart account: ${errorMessage}`
      );
    }
  }
);
