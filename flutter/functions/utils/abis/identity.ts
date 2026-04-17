export const identityABI = [
  {
    name: "identities",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [
      { name: "dateAuthenticated", type: "uint256" },
      { name: "dateAdded", type: "uint256" },
      { name: "did", type: "string" },
      { name: "whitelistedOnChainId", type: "uint256" },
      { name: "status", type: "uint8" },
      { name: "authCount", type: "uint32" },
    ],
  },
] as const;
