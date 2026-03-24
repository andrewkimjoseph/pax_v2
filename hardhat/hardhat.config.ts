import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-verify";
import { Address } from "viem";
import * as dotenv from "dotenv";
dotenv.config();

const rawPk = process.env.SEND_TOKEN_PK ?? process.env.PK_ONE;
const INFURA_API_KEY = process.env.INFURA_API_KEY;
const ETHERSCAN_API_KEY =
  process.env.ETHERSCAN_API_KEY ?? process.env.CELOSCAN_API_KEY;

if (!rawPk) {
  throw new Error("SEND_TOKEN_PK or PK_ONE not found in environment variables");
}
if (!INFURA_API_KEY)
  throw new Error("INFURA_API_KEY not found in environment variables");
if (!ETHERSCAN_API_KEY)
  throw new Error(
    "ETHERSCAN_API_KEY (or fallback CELOSCAN_API_KEY) not found in environment variables"
  );

const ALFAJORES_INFURA_RPC_URL = `https://celo-alfajores.infura.io/v3/${INFURA_API_KEY}`;

const MAINNET_INFURA_RPC_URL = `https://celo-mainnet.infura.io/v3/${INFURA_API_KEY}`;

const normalizedPk = rawPk.startsWith("0x") ? rawPk : `0x${rawPk}`;
const PK = normalizedPk as Address;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.34",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
      evmVersion: "cancun",
    },
  },
  networks: {
    celoAlfajores: {
      url: ALFAJORES_INFURA_RPC_URL,
      accounts: [PK],
      chainId: 44787,
    },
    celo: {
      url: MAINNET_INFURA_RPC_URL,
      accounts: [PK],
      chainId: 42220,
    },
  },
  sourcify: {
    enabled: true
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
    customChains: [
      {
        network: "celoAlfajores",
        chainId: 44787,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api",
          browserURL: "https://alfajores.celoscan.io",
        },
      },
      {
        network: "celo",
        chainId: 42220,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api",
          browserURL: "https://celoscan.io",
        },
      },
    ],
  },
};

export default config;