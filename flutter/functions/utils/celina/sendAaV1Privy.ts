import { preparedStepsToUserOpCalls } from "@andrewkimjoseph/celina-sdk";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { http, type Address, type Hex } from "viem";
import { entryPoint07Address } from "viem/account-abstraction";
import { celo } from "viem/chains";
import { CANVASSING_ATTRIBUTION_TAGS } from "./client";
import { PIMLICO_URL } from "../config";

export type PrivyUserOpCall = {
  to: Address;
  value?: bigint;
  data: Hex;
};

export async function sendPrivySponsoredUserOp(params: {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  smartAccount: any;
  calls: PrivyUserOpCall[];
  logPrefix?: string;
}): Promise<{ bundleTxnHash: Hex; userOpHash: Hex }> {
  const { createPimlicoClient } = await import(
    "permissionless/clients/pimlico"
  );
  const { createSmartAccountClient } = await import("permissionless");

  const pimlicoClient = createPimlicoClient({
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
    paymaster: pimlicoClient,
    userOperation: {
      estimateFeesPerGas: async () =>
        (await pimlicoClient.getUserOperationGasPrice()).fast,
    },
  });

  const steps = params.calls.map((call, index) => ({
    kind: "contract" as const,
    to: call.to,
    data: call.data,
    value: call.value !== undefined ? call.value.toString() : undefined,
    description: `call ${index + 1}`,
  }));

  const taggedCalls = preparedStepsToUserOpCalls(steps, [
    ...CANVASSING_ATTRIBUTION_TAGS,
  ]);

  if (params.logPrefix) {
    logger.info(`${params.logPrefix} Submitting sponsored userOp`, {
      callCount: taggedCalls.length,
    });
  }

  const userOpHash = await smartAccountClient.sendUserOperation({
    calls: taggedCalls,
  });

  const userOpReceipt = await smartAccountClient.waitForUserOperationReceipt({
    hash: userOpHash,
  });

  if (!userOpReceipt.success) {
    throw new HttpsError(
      "internal",
      `User operation failed: ${JSON.stringify(userOpReceipt)}`
    );
  }

  return {
    bundleTxnHash: userOpReceipt.receipt.transactionHash,
    userOpHash,
  };
}
