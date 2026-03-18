import { Address } from "viem";
import {
  CANVASSING_WALLET_REGISTRY_PROXY_ADDRESS,
  PUBLIC_CLIENT,
} from "./config";
import { canvassingWalletRegistryABI } from "./abis/canvassingWalletRegistry";

/**
 * Returns true if the given EO wallet address has already been logged
 * in the CanvassingWalletRegistry contract.
 */
export async function isWalletAlreadyLogged(
  eoWalletAddress: Address
): Promise<boolean> {
  const isLogged = await PUBLIC_CLIENT.readContract({
    address: CANVASSING_WALLET_REGISTRY_PROXY_ADDRESS,
    abi: canvassingWalletRegistryABI,
    functionName: "isWalletLogged",
    args: [eoWalletAddress],
  });

  return Boolean(isLogged);
}

