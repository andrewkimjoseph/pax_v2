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

  const walletAccount = params.walletClient.account;
  if (
    typeof walletAccount !== "object" ||
    walletAccount === null ||
    !("signTransaction" in walletAccount)
  ) {
    throw new HttpsError(
      "failed-precondition",
      "walletClient must be created with a local signing account"
    );
  }

  return params.walletClient.sendTransaction({
    account: walletAccount,
    chain: params.walletClient.chain,
    to: step.to,
    data: step.data,
    value: step.value ? BigInt(step.value) : undefined,
  });
}
