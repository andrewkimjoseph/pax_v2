import { appendCelinaCalldataTag } from "@andrewkimjoseph/celina-sdk";
import type { Hex } from "viem";

/** App attribution tags appended after platform `celina` (ERC-8021 Schema 0). */
export const CANVASSING_ATTRIBUTION_TAGS = ["canvassing"] as const;

/** Append Celina ERC-8021 attribution (`celina`, `canvassing`) to prepared calldata. */
export function tagCalldata(data: Hex): Hex {
  return appendCelinaCalldataTag(data, [...CANVASSING_ATTRIBUTION_TAGS]);
}
