import { createCelinaClient } from "@andrewkimjoseph/celina-sdk";
import { DRPC_URL } from "../config";

export const CANVASSING_ATTRIBUTION_TAGS = ["canvassing"] as const;

export const celinaClient = createCelinaClient({
  rpcUrl: DRPC_URL,
  attributionTags: [...CANVASSING_ATTRIBUTION_TAGS],
  analyticsDeviceId: "pax",
});
