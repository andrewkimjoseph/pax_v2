import type { Address } from "viem";
import {
  IDENTITY_PROXY_CONTRACT_ADDRESS,
  PUBLIC_CLIENT,
  WHITELIST_ABI,
} from "../config";

export async function isWalletWhitelisted(eoAddress: Address): Promise<boolean> {
  return PUBLIC_CLIENT.readContract({
    address: IDENTITY_PROXY_CONTRACT_ADDRESS,
    abi: WHITELIST_ABI,
    functionName: "isWhitelisted",
    args: [eoAddress],
  });
}
