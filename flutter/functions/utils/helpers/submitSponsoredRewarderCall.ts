import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { http } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { celo } from "viem/chains";
import {
  CANVASSING_REWARDER_PROXY_ADDRESS,
  PIMLICO_URL,
} from "../config";

/**
 * Submit a sponsored userOp that calls the CanvassingRewarder proxy with arbitrary calldata.
 * Used for claimTaskReward and claimAchievementReward (msg.sender = participant smart account).
 */
export async function submitSponsoredRewarderCall(params: {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  smartAccount: any;
  data: `0x${string}`;
  logPrefix: string;
}): Promise<{ bundleTxnHash: `0x${string}` }> {
  const { createPimlicoClient } = await import(
    "permissionless/clients/pimlico"
  );
  const { createSmartAccountClient } = await import("permissionless");

  const PIMLICO_CLIENT = createPimlicoClient({
    transport: http(PIMLICO_URL),
    entryPoint: {
      address: entryPoint07Address,
      version: "0.7",
    },
  });

  const smartAccountClient = createSmartAccountClient({
    account: params.smartAccount,
    chain: celo,
    bundlerTransport: http(PIMLICO_URL),
    paymaster: PIMLICO_CLIENT,
    userOperation: {
      estimateFeesPerGas: async () => {
        return (await PIMLICO_CLIENT.getUserOperationGasPrice()).fast;
      },
    },
  });

  logger.info(
    `${params.logPrefix} Submitting sponsored CanvassingRewarder userOp`
  );

  const userOpTxnHash = await smartAccountClient.sendUserOperation({
    calls: [
      {
        to: CANVASSING_REWARDER_PROXY_ADDRESS,
        value: BigInt(0),
        data: params.data,
      },
    ],
  });

  const userOpReceipt =
    await smartAccountClient.waitForUserOperationReceipt({
      hash: userOpTxnHash,
    });

  if (!userOpReceipt.success) {
    logger.error(`${params.logPrefix} Rewarder userOp failed`, {
      userOpReceipt,
    });
    throw new HttpsError(
      "internal",
      `User operation failed: ${JSON.stringify(userOpReceipt)}`
    );
  }

  return { bundleTxnHash: userOpReceipt.receipt.transactionHash };
}
