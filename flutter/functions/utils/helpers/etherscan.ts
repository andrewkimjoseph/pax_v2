import { logger } from "firebase-functions/v2";
import {
  ETHERSCAN_API_KEY_1,
  ETHERSCAN_API_KEY_2,
  ETHERSCAN_API_KEY_3,
  ETHERSCAN_API_KEY_4,
  ETHERSCAN_V2_BASE_URL,
} from "../config";
import { celo } from "viem/chains";

/** Round-robin index for Etherscan API keys. */
let etherscanKeyIndex = 0;

/** Celo Blockscout REST API — no API key; used when Etherscan is rate-limited. */
const CELO_BLOCKSCOUT_BASE_URL = "https://celo.blockscout.com/api/v2";

function isRateLimitedResult(result: unknown): boolean {
  if (typeof result !== "string") return false;
  const lower = result.toLowerCase();
  return (
    lower.includes("rate limit") ||
    lower.includes("max rate") ||
    lower.includes("api limit reached") ||
    lower.includes("community free api limit")
  );
}

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
 * Returns configured Etherscan API keys (non-empty only).
 */
export function getEtherscanApiKeys(): string[] {
  return [
    ETHERSCAN_API_KEY_1,
    ETHERSCAN_API_KEY_2,
    ETHERSCAN_API_KEY_3,
    ETHERSCAN_API_KEY_4,
  ].filter(Boolean);
}

/**
 * Returns the next Etherscan API key in round-robin order.
 * @throws Error if no keys are configured.
 */
export function getNextEtherscanApiKey(): string {
  const keys = getEtherscanApiKeys();
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

interface BlockscoutTokenTransfer {
  block_number?: number;
  timestamp?: string;
  transaction_hash?: string;
  from?: { hash?: string };
  to?: { hash?: string };
  token?: {
    address_hash?: string;
    name?: string;
    symbol?: string;
    decimals?: string | number;
  };
  total?: { value?: string; decimals?: string | number };
  method?: string;
}

/**
 * Maps a Blockscout token-transfer item to the Etherscan tokentx shape used by the app.
 */
export function mapBlockscoutTransferToEtherscanTx(
  item: BlockscoutTokenTransfer
): EtherscanTx {
  const tsMs = item.timestamp ? Date.parse(item.timestamp) : NaN;
  const timeStamp = Number.isFinite(tsMs)
    ? String(Math.floor(tsMs / 1000))
    : undefined;
  return {
    blockNumber:
      item.block_number !== undefined ? String(item.block_number) : undefined,
    timeStamp,
    hash: item.transaction_hash,
    from: item.from?.hash,
    to: item.to?.hash,
    value: item.total?.value,
    contractAddress: item.token?.address_hash,
    tokenName: item.token?.name,
    tokenSymbol: item.token?.symbol,
    tokenDecimal:
      item.token?.decimals !== undefined
        ? String(item.token.decimals)
        : undefined,
    functionName: item.method,
    isError: "0",
    txreceipt_status: "1",
  };
}

/**
 * Fetches ERC-20 token transfers from Celo Blockscout (no API key).
 */
export async function fetchBlockscoutTxList(
  params: FetchTxListParams
): Promise<{ status: string; message: string; result: EtherscanTx[] }> {
  const { page = 1, offset = 20 } = params;
  const address = params.address.trim().toLowerCase().startsWith("0x")
    ? params.address.trim().toLowerCase()
    : `0x${params.address.trim().toLowerCase()}`;

  // Blockscout first page is newest-first; we only request page 1 from callers today.
  const url = `${CELO_BLOCKSCOUT_BASE_URL}/addresses/${address}/token-transfers?type=ERC-20`;
  const response = await fetch(url);
  if (!response.ok) {
    logger.warn("Blockscout API HTTP error", {
      status: response.status,
      address,
    });
    throw new Error(`Blockscout API returned ${response.status}`);
  }

  const data = (await response.json()) as {
    items?: BlockscoutTokenTransfer[];
  };
  const items = Array.isArray(data.items) ? data.items : [];
  const start = Math.max(0, (page - 1) * offset);
  const sliced = items.slice(start, start + offset);
  const result = sliced.map(mapBlockscoutTransferToEtherscanTx);

  return {
    status: result.length > 0 ? "1" : "0",
    message: result.length > 0 ? "OK" : "No transactions found",
    result,
  };
}

/**
 * Fetches transaction list from Etherscan v2 API, rotating keys on rate-limit.
 * Falls back to Celo Blockscout when all Etherscan keys are exhausted / rate-limited.
 */
export async function fetchEtherscanTxList(
  params: FetchTxListParams
): Promise<{ status: string; message: string; result: EtherscanTx[] }> {
  const keys = getEtherscanApiKeys();
  if (keys.length === 0) {
    logger.warn("No Etherscan keys; using Blockscout fallback");
    return fetchBlockscoutTxList(params);
  }

  let lastError: Error | null = null;
  let sawRateLimit = false;

  for (let attempt = 0; attempt < keys.length; attempt++) {
    const apiKey = getNextEtherscanApiKey();
    const url = buildEtherscanTxListUrl(params, apiKey);

    try {
      const response = await fetch(url);
      if (!response.ok) {
        lastError = new Error(`Etherscan API returned ${response.status}`);
        logger.warn("Etherscan API HTTP error", {
          status: response.status,
          address: params.address,
        });
        continue;
      }

      const data = (await response.json()) as EtherscanTxListResponse;

      if (data.status !== "1" && data.message !== "No transactions found") {
        if (isRateLimitedResult(data.result)) {
          sawRateLimit = true;
          lastError = new Error(
            typeof data.result === "string" ? data.result : "Etherscan rate limit"
          );
          logger.warn("Etherscan rate limited; trying next key", {
            address: params.address,
            result:
              typeof data.result === "string"
                ? data.result.slice(0, 160)
                : data.result,
          });
          continue;
        }
        logger.warn("Etherscan API error response", {
          message: data.message,
          result:
            typeof data.result === "string"
              ? data.result.slice(0, 160)
              : data.result,
          address: params.address,
        });
        lastError = new Error(
          (typeof data.result === "string" && data.result) ||
            data.message ||
            "Etherscan API error"
        );
        continue;
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
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
    }
  }

  if (sawRateLimit || lastError) {
    logger.warn("Etherscan exhausted; falling back to Blockscout", {
      address: params.address,
      sawRateLimit,
      lastError: lastError?.message,
    });
    try {
      return await fetchBlockscoutTxList(params);
    } catch (fallbackErr) {
      throw lastError ??
        (fallbackErr instanceof Error
          ? fallbackErr
          : new Error(String(fallbackErr)));
    }
  }

  throw lastError ?? new Error("Etherscan API error");
}
