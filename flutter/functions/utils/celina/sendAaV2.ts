import { celo } from "viem/chains";
import type { Address, Hex } from "viem";
import { HttpsError } from "firebase-functions/v2/https";
import { createCelinaAAClient } from "./aaClient";

export type PreparedContractStep = {
  kind: "contract" | "erc20";
  to: Address;
  data: Hex;
  description: string;
};

export async function sendCelinaPreparedFlow(params: {
  privateKeyHex: Hex;
  steps: PreparedContractStep[];
  summary: string;
}): Promise<{ bundleTxnHash: Hex; userOpHash: Hex }> {
  const aa = await createCelinaAAClient(params.privateKeyHex);

  const result = await aa.sendPreparedFlow({
    preparedFlow: true,
    chainId: celo.id,
    from: aa.smartAccountAddress,
    summary: params.summary,
    steps: params.steps,
  });

  if (!result.success) {
    throw new HttpsError("internal", "User operation failed");
  }

  return {
    bundleTxnHash: result.transactionHashes[0]!,
    userOpHash: result.userOpHashes[0]!,
  };
}
