/**
 * Temporary script: send ERC20 tokens from the smart account controlled by PK in .env.
 *
 * Required in .env:
 *   - PK (or SEND_TOKEN_PK): private key of the EOA that owns the smart account (hex, no 0x prefix)
 *   - SEND_TOKEN_TO: recipient address (0x...)
 *
 * Optional in .env:
 *   - SEND_TOKEN_TOKEN: ERC20 token address (default: GoodDollar mainnet)
 *   - SEND_TOKEN_AMOUNT: amount in token units (18 decimals), e.g. "6250000" (default: "6250000")
 *
 * Run from project root (hardhat/):
 *   npx ts-node test/deploy/sendTokenFromSmartAccount.ts
 *
 * Or from repo root:
 *   npx ts-node --project hardhat hardhat/test/deploy/sendTokenFromSmartAccount.ts
 */

import { config } from "dotenv";
import { Address, encodeFunctionData, parseEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { entryPoint07Address } from "viem/account-abstraction";
import { celo } from "viem/chains";
import { http } from "viem";
import { createSmartAccountClient } from "permissionless";
import { toSimpleSmartAccount } from "permissionless/accounts";
import {
  publicClient,
  pimlicoClient,
  pimlicoUrl,
  waitForUserOperationReceipt,
} from "../utils/clients";
import { erc20ABI } from "../abis/erc20";

// GoodDollar on Celo mainnet
const GOODDOLLAR_ADDRESS = "0x62B8B11039FcfE5aB0C56E502b1C372A3d2a9c7A" as Address;

config();

const PK_HEX =
  (process.env.SEND_TOKEN_PK ?? process.env.PK)?.startsWith("0x")
    ? (process.env.SEND_TOKEN_PK ?? process.env.PK)
    : `0x${process.env.SEND_TOKEN_PK ?? process.env.PK}`;

const TO_ADDRESS = "0x9cfa5C4BFE08A1A3F7c17D6503EeB23A0290c4Ca";
const TOKEN_ADDRESS = (process.env.SEND_TOKEN_TOKEN ?? GOODDOLLAR_ADDRESS) as Address;
const AMOUNT_STR = process.env.SEND_TOKEN_AMOUNT ?? "13773799";

async function main() {
  if (!PK_HEX || PK_HEX === "0xundefined") {
    throw new Error("Missing PK or SEND_TOKEN_PK in .env");
  }
  if (!TO_ADDRESS || !TO_ADDRESS.startsWith("0x")) {
    throw new Error("Missing or invalid SEND_TOKEN_TO in .env (must be 0x... address)");
  }

  const amount = parseEther(AMOUNT_STR);
  console.log("Send token from smart account (EOA owner from PK)");
  console.log("  Recipient:", TO_ADDRESS);
  console.log("  Token: GoodDollar", TOKEN_ADDRESS);
  console.log("  Amount:", AMOUNT_STR, "G$ (", amount.toString(), "wei )");

  const owner = privateKeyToAccount(PK_HEX as `0x${string}`);
  const safeSmartAccount = await toSimpleSmartAccount({
    client: publicClient,
    owner,
    entryPoint: {
      address: entryPoint07Address,
      version: "0.7",
    },
  });

  const smartAccountClient = createSmartAccountClient({
    account: safeSmartAccount,
    chain: celo,
    bundlerTransport: http(pimlicoUrl),
    paymaster: pimlicoClient,
    userOperation: {
      estimateFeesPerGas: async () => {
        return (await pimlicoClient.getUserOperationGasPrice()).fast;
      },
    },
  });

  const transferData = encodeFunctionData({
    abi: erc20ABI,
    functionName: "transfer",
    args: [TO_ADDRESS, amount],
  });

  const userOpHash = await smartAccountClient.sendUserOperation({
    calls: [
      {
        to: TOKEN_ADDRESS,
        value: 0n,
        data: transferData,
      },
    ],
  });

  console.log("User operation hash:", userOpHash);

  const receipt = await waitForUserOperationReceipt(smartAccountClient, userOpHash);
  console.log("Bundle tx hash:", receipt.receipt.transactionHash);
  console.log("Done.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
