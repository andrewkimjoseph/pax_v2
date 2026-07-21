import type { Hex } from "viem";
import { CANVASSING_REWARDER_PROXY_ADDRESS } from "../config";
import { sendCelinaPreparedFlow } from "../celina/sendAaV2";
import { sendPrivySponsoredUserOp } from "../celina/sendAaV1Privy";

/**
 * Submit a sponsored userOp that calls the CanvassingRewarder proxy with arbitrary calldata.
 * Used for claimTaskReward and claimAchievementReward (msg.sender = participant smart account).
 */
export async function submitSponsoredRewarderCall(
  params:
    | {
        path: "v1";
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        smartAccount: any;
        data: Hex;
        logPrefix: string;
      }
    | {
        path: "v2";
        privateKeyHex: Hex;
        data: Hex;
        logPrefix: string;
      }
): Promise<{ bundleTxnHash: Hex }> {
  if (params.path === "v2") {
    const result = await sendCelinaPreparedFlow({
      privateKeyHex: params.privateKeyHex,
      steps: [
        {
          kind: "contract",
          to: CANVASSING_REWARDER_PROXY_ADDRESS,
          data: params.data,
          description: `${params.logPrefix} CanvassingRewarder call`,
        },
      ],
      summary: `${params.logPrefix} CanvassingRewarder call`,
    });
    return { bundleTxnHash: result.bundleTxnHash };
  }

  const result = await sendPrivySponsoredUserOp({
    smartAccount: params.smartAccount,
    calls: [
      {
        to: CANVASSING_REWARDER_PROXY_ADDRESS,
        value: BigInt(0),
        data: params.data,
      },
    ],
    logPrefix: params.logPrefix,
  });

  return { bundleTxnHash: result.bundleTxnHash };
}
