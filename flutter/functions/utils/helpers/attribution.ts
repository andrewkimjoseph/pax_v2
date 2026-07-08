import { concat, stringToHex, type Hex } from "viem";

/** Calldata suffix appended to prepared transactions for on-chain attribution. */
export const CANVASSING_DATA_SUFFIX = stringToHex("CANVASSING");

export function appendDataSuffix(
  data: Hex,
  suffix: Hex = CANVASSING_DATA_SUFFIX
): Hex {
  return concat([data, suffix]);
}

export function CANVASSINGTaggedCallData(
  data: Hex,
  suffix: Hex = CANVASSING_DATA_SUFFIX
): Hex {
  return appendDataSuffix(data, suffix);
}

export function hasDataSuffix(
  data: Hex,
  suffix: Hex = CANVASSING_DATA_SUFFIX
): boolean {
  const suffixBody = suffix.slice(2).toLowerCase();
  return data.slice(2).toLowerCase().endsWith(suffixBody);
}

export function stripDataSuffix(
  data: Hex,
  suffix: Hex = CANVASSING_DATA_SUFFIX
): Hex {
  if (!hasDataSuffix(data, suffix)) {
    return data;
  }
  const suffixBody = suffix.slice(2);
  return `0x${data.slice(2, data.length - suffixBody.length)}` as Hex;
}
