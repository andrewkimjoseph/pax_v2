/**
 * Helper script: withdraw all reward tokens from a TaskManager to the task master
 * (smart account), then transfer them to WITHDRAW_REWARD_TO_ADDRESS — in one sponsored user op.
 *
 * Uses the Privy task-manager wallet (WALLET_IDS.TASK_MANAGER). No PK. Contract addresses
 * and recipient are constants in ../utils/helpers (TASK_MANAGER_ADDRESS, WITHDRAW_REWARD_TO_ADDRESS).
 *
 * Run from project root (hardhat/):
 *   npx ts-node test/deploy/withdrawRewardToWallet.ts
 *
 * Or from repo root:
 *   npx ts-node --project hardhat hardhat/test/deploy/withdrawRewardToWallet.ts
 */

import { encodeFunctionData } from "viem";
import {
  publicClient,
  waitForUserOperationReceipt,
} from "../utils/clients";
import { TASK_MANAGER_ADDRESS, WITHDRAW_REWARD_TO_ADDRESS } from "../utils/helpers";
import { WALLET_IDS, getWalletInfo } from "../utils/wallets";
import { erc20ABI } from "../abis/erc20";

// Minimal ABI for TaskManagerV2: withdraw + view functions we need
const taskManagerV2WithdrawABI = [
  {
    inputs: [],
    name: "withdrawAllRewardTokenToTaskMaster",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "getRewardTokenContractAddress",
    outputs: [{ internalType: "contract IERC20", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getRewardTokenContractBalanceAmount",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

async function main() {
  if (TASK_MANAGER_ADDRESS === "0x0000000000000000000000000000000000000000") {
    throw new Error("Set TASK_MANAGER_ADDRESS in test/utils/helpers.ts");
  }

  const taskManagerWallet = await getWalletInfo(WALLET_IDS.TASK_MANAGER);
  const { client: smartAccountClient } = taskManagerWallet;
  const taskManager = TASK_MANAGER_ADDRESS;

  const [rewardTokenAddress, balance] = await Promise.all([
    publicClient.readContract({
      address: taskManager,
      abi: taskManagerV2WithdrawABI,
      functionName: "getRewardTokenContractAddress",
    }),
    publicClient.readContract({
      address: taskManager,
      abi: taskManagerV2WithdrawABI,
      functionName: "getRewardTokenContractBalanceAmount",
    }),
  ]);

  if (balance === 0n) {
    console.log("TaskManager has no reward tokens to withdraw. Exiting.");
    process.exit(0);
  }

  console.log("Withdraw reward tokens from TaskManager to task master, then to recipient");
  console.log("  TaskManager:", taskManager);
  console.log("  Reward token:", rewardTokenAddress);
  console.log("  Amount (wei):", balance.toString());
  console.log("  Recipient:", WITHDRAW_REWARD_TO_ADDRESS);

  const withdrawData = encodeFunctionData({
    abi: taskManagerV2WithdrawABI,
    functionName: "withdrawAllRewardTokenToTaskMaster",
  });

  const transferData = encodeFunctionData({
    abi: erc20ABI,
    functionName: "transfer",
    args: [WITHDRAW_REWARD_TO_ADDRESS, balance],
  });

  const userOpHash = await smartAccountClient.sendUserOperation({
    calls: [
      { to: taskManager, value: 0n, data: withdrawData },
      { to: rewardTokenAddress, value: 0n, data: transferData },
    ],
  });

  console.log("User operation hash:", userOpHash);

  const receipt = await waitForUserOperationReceipt(smartAccountClient, userOpHash);
  console.log("Bundle tx hash:", receipt.receipt.transactionHash);
  console.log("Done.");
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
