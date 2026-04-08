import type { Address } from "viem";
import {
  IDENTITY_PROXY_CONTRACT_ADDRESS,
  PUBLIC_CLIENT,
  WHITELIST_ABI,
} from "../config";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export async function isWalletWhitelisted(eoAddress: Address): Promise<boolean> {
  const whitelistedRoot = (await PUBLIC_CLIENT.readContract({
    address: IDENTITY_PROXY_CONTRACT_ADDRESS,
    abi: WHITELIST_ABI,
    functionName: "getWhitelistedRoot",
    args: [eoAddress],
  })) as Address;

  return whitelistedRoot.toLowerCase() !== ZERO_ADDRESS;
}
