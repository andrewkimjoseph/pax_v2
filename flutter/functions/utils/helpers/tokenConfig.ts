import type { Address } from "viem";
import {
  GOOD_DOLLAR_TOKEN_ADDRESS,
  USDM_TOKEN_ADDRESS,
  USDT_TOKEN_ADDRESS,
  USDC_TOKEN_ADDRESS,
} from "../config";

type TokenConfig = {
  tokenAddress: Address;
  decimals: number;
};

/**
 * 1: GoodDollar (18)
 * 2: USDM (18)
 * 3: USDT (6)
 * 4: USDC (6)
 */
export function getTokenConfigForCurrencyId(currencyId: number): TokenConfig {
  switch (currencyId) {
    case 1:
      return { tokenAddress: GOOD_DOLLAR_TOKEN_ADDRESS, decimals: 18 };
    case 2:
      return { tokenAddress: USDM_TOKEN_ADDRESS, decimals: 18 };
    case 3:
      return { tokenAddress: USDT_TOKEN_ADDRESS, decimals: 6 };
    case 4:
      return { tokenAddress: USDC_TOKEN_ADDRESS, decimals: 6 };
    default:
      throw new Error(`Unsupported rewardCurrencyId: ${currencyId}`);
  }
}

