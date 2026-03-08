import { logger } from "firebase-functions/v2";
import {
  ETHERSCAN_API_KEY_1,
  ETHERSCAN_API_KEY_2,
  ETHERSCAN_V2_BASE_URL,
} from "../config";
import { celo } from "viem/chains";

/** Round-robin index for Etherscan API keys. */
let etherscanKeyIndex = 0;

export interface EtherscanApiUsageResult {
  creditsUsed: number;
  creditsAvailable: number;
  creditLimit: number;
  limitInterval: string;
  intervalExpiryTimespan: string;
}

/**
 * Fetches current Etherscan API credit usage and limit for the given API key.
 * GET .../v2/api?apikey=...&module=getapilimit&action=getapilimit
 */
export async function getEtherscanApiUsage(
  apiKey: string
): Promise<EtherscanApiUsageResult | null> {
  try {
    const url = new URL(ETHERSCAN_V2_BASE_URL);
    url.searchParams.set("apikey", apiKey);
    url.searchParams.set("module", "getapilimit");
    url.searchParams.set("action", "getapilimit");

    const response = await fetch(url.toString());
    if (!response.ok) return null;

    const data = (await response.json()) as {
      status: string;
      message: string;
      result?: EtherscanApiUsageResult;
    };
    if (data.status !== "1" || !data.result) return null;

    return data.result;
  } catch {
    return null;
  }
}

/**
 * Returns the next Etherscan API key in round-robin order.
 * @throws Error if no keys are configured.
 */
export function getNextEtherscanApiKey(): string {
  const keys = [ETHERSCAN_API_KEY_1, ETHERSCAN_API_KEY_2].filter(Boolean);
  if (keys.length === 0) {
    throw new Error("Etherscan API keys not configured.");
  }
  const key = keys[etherscanKeyIndex % keys.length];
  etherscanKeyIndex += 1;
  return key;
}

export interface EtherscanTx {
  blockNumber?: string;
  timeStamp?: string;
  hash?: string;
  from?: string;
  to?: string;
  value?: string;
  gasUsed?: string;
  gasPrice?: string;
  functionName?: string;
  isError?: string;
  txreceipt_status?: string;
  input?: string;
  contractAddress?: string;
  cumulativeGasUsed?: string;
  confirmations?: string;
  methodId?: string;
  /** ERC-20 tokentx fields */
  tokenName?: string;
  tokenSymbol?: string;
  tokenDecimal?: string;
  [key: string]: unknown;
}

export interface EtherscanTxListResponse {
  status: string;
  message: string;
  result: EtherscanTx[] | string;
}

export interface FetchTxListParams {
  address: string;
  page?: number;
  offset?: number;
}

/**
 * Builds the Etherscan v2 API URL for account ERC-20 token transfers (tokentx).
 */
export function buildEtherscanTxListUrl(
  params: FetchTxListParams,
  apiKey: string
): string {
  const { page = 1, offset = 20 } = params;
  // Etherscan indexes by lowercase address; use normalized form for consistent results.
  const address = params.address.trim().toLowerCase().startsWith("0x")
    ? params.address.trim().toLowerCase()
    : `0x${params.address.trim().toLowerCase()}`;
  const url = new URL(ETHERSCAN_V2_BASE_URL);
  url.searchParams.set("apikey", apiKey);
  url.searchParams.set("chainid", String(celo.id));
  url.searchParams.set("address", address);
  url.searchParams.set("module", "account");
  url.searchParams.set("action", "tokentx");
  url.searchParams.set("page", String(page));
  url.searchParams.set("offset", String(offset));
  url.searchParams.set("sort", "desc");
  return url.toString();
}

/**
 * Fetches transaction list from Etherscan v2 API.
 * Uses round-robin API key. Returns parsed result array; throws on HTTP or API error.
 */
export async function fetchEtherscanTxList(
  params: FetchTxListParams
): Promise<{ status: string; message: string; result: EtherscanTx[] }> {
  const apiKey = getNextEtherscanApiKey();
  const url = buildEtherscanTxListUrl(params, apiKey);

  const response = await fetch(url);
  if (!response.ok) {
    logger.warn("Etherscan API HTTP error", {
      status: response.status,
      address: params.address,
    });
    throw new Error(`Etherscan API returned ${response.status}`);
  }

  const data = (await response.json()) as EtherscanTxListResponse;
  if (data.status !== "1" && data.message !== "No transactions found") {
    logger.warn("Etherscan API error response", {
      message: data.message,
      address: params.address,
    });
    throw new Error(data.message || "Etherscan API error");
  }

  const usage = await getEtherscanApiUsage(apiKey);
  if (usage) {
    logger.info("Etherscan API usage", {
      creditsUsed: usage.creditsUsed,
      creditsAvailable: usage.creditsAvailable,
      creditLimit: usage.creditLimit,
      limitInterval: usage.limitInterval,
      intervalExpiryTimespan: usage.intervalExpiryTimespan,
    });
  }

  let result: EtherscanTx[] = [];
  if (Array.isArray(data.result)) {
    result = data.result;
  } else if (
    typeof data.result === "string" &&
    data.result !== "No transactions found"
  ) {
    logger.warn("Unexpected Etherscan result type", { result: data.result });
  }

  return {
    status: data.status,
    message: data.message,
    result,
  };
}
