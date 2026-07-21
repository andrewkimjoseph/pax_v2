import type { Abi, Address, Hash, WalletClient } from "viem";
import { HttpsError } from "firebase-functions/v2/https";
import { celinaClient } from "./client";

export async function sendEoaPreparedContractCall(params: {
  from: Address;
  walletClient: WalletClient;
  contractAddress: Address;
  abi: Abi;
  functionName: string;
  args: unknown[];
}): Promise<Hash> {
  const prepared = await celinaClient.contract.prepareFunction(params.from, {
    contractAddress: params.contractAddress,
    abi: params.abi,
    functionName: params.functionName,
    functionArgs: params.args,
  });

  const step = prepared.steps[0];
  if (!step?.to || !step.data) {
    throw new HttpsError(
      "internal",
      "prepareFunction returned no valid step"
    );
  }

  return params.walletClient.sendTransaction({
    account: params.from,
    chain: params.walletClient.chain,
    to: step.to,
    data: step.data,
    value: step.value ? BigInt(step.value) : undefined,
  });
}
