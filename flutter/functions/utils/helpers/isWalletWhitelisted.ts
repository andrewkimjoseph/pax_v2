import type { Address } from "viem";
import {
  IDENTITY_PROXY_CONTRACT_ADDRESS,
  PUBLIC_CLIENT,
} from "../config";
import { identityABI } from "../abis/identity";

export async function isWalletWhitelisted(eoAddress: Address): Promise<boolean> {
  const identity = await PUBLIC_CLIENT.readContract({
    address: IDENTITY_PROXY_CONTRACT_ADDRESS,
    abi: identityABI,
    functionName: "identities",
    args: [eoAddress],
  });

  const status = Number(identity[4]);
  return status === 1;
}
