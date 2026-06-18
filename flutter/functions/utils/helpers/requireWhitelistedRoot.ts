import { HttpsError } from "firebase-functions/v2/https";
import type { Address } from "viem";
import { zeroAddress } from "viem";
import {
  IDENTITY_PROXY_CONTRACT_ADDRESS,
  PUBLIC_CLIENT,
} from "../config";
import { identityABI } from "../abis/identity";

/**
 * Ensures [address] is GoodDollar verified and is the identity root itself
 * (not a connected wallet under another root). Used for V1 first withdrawal link.
 */
export async function requireWhitelistedRoot(address: Address): Promise<void> {
  const root = await PUBLIC_CLIENT.readContract({
    address: IDENTITY_PROXY_CONTRACT_ADDRESS,
    abi: identityABI,
    functionName: "getWhitelistedRoot",
    args: [address],
  });

  if (root === zeroAddress) {
    throw new HttpsError(
      "failed-precondition",
      "Wallet not GoodDollar verified"
    );
  }

  if (root.toLowerCase() !== address.toLowerCase()) {
    throw new HttpsError(
      "failed-precondition",
      "Wallet must be the whitelisted identity root, not a linked wallet"
    );
  }
}
