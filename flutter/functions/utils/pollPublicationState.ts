export function isPollPublished(reviewStatus: string | null): boolean {
  return reviewStatus === "published";
}

export function isPollActiveOnPax(input: {
  isActive: boolean | null;
  deadline: string | null;
  now?: Date;
}): boolean {
  if (input.isActive !== true) return false;
  if (input.deadline && new Date(input.deadline) <= (input.now ?? new Date())) return false;
  return true;
}
