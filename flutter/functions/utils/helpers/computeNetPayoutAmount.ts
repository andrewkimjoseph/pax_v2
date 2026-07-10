/**
 * Net wallet payout after optional impact donation split.
 * donationBasisPoints uses 10000 = 100% (e.g. 1000 = 10%).
 */
export function computeNetPayoutAmount(
  grossAmount: number,
  hasDonationSplit: boolean,
  donationBasisPoints?: number
): number {
  if (!hasDonationSplit) return grossAmount;
  return Number(
    ((grossAmount * (10000 - Number(donationBasisPoints))) / 10000).toFixed(12)
  );
}
