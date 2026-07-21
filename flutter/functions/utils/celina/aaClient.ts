import { createAAClient, type AAClient } from "@andrewkimjoseph/celina-sdk";
import type { Hex } from "viem";
import { CANVASSING_ATTRIBUTION_TAGS } from "./client";
import { PIMLICO_API_KEY, PUBLIC_CLIENT } from "../config";

export async function createCelinaAAClient(
  owner: Hex
): Promise<AAClient> {
  return createAAClient({
    owner,
    attributionTags: [...CANVASSING_ATTRIBUTION_TAGS],
    gasSponsorship: {
      provider: "pimlico",
      pimlico: { apiKey: PIMLICO_API_KEY },
    },
    publicClient: PUBLIC_CLIENT as never,
  });
}
