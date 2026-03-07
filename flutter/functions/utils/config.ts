import { Address, createPublicClient, http } from 'viem';
import { CallableOptions } from 'firebase-functions/v2/https';
import { config } from 'dotenv';
import { celo } from 'viem/chains';
import { PrivyClient } from '@privy-io/server-auth';
import * as admin from "firebase-admin";
import { privateKeyToAccount } from 'viem/accounts';

config();

export const PRIVY_APP_ID = process.env.PRIVY_APP_ID || '';
export const PRIVY_APP_SECRET = process.env.PRIVY_APP_SECRET || '';
export const PRIVY_WALLET_AUTH_PRIVATE_KEY = process.env.PRIVY_WALLET_AUTH_PRIVATE_KEY || '';
export const PIMLICO_API_KEY = process.env.PIMLICO_API_KEY || '';
export const DRPC_API_KEY = process.env.DRPC_API_KEY || '';
export const PAX_MASTER_PRIVATE_KEY = process.env.PAX_MASTER_PRIVATE_KEY || '';

export const PAXACCOUNT_V1_IMPLEMENTATION_ADDRESS = process.env.PAXACCOUNT_V1_IMPLEMENTATION_ADDRESS as Address;
export const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || '';
export const TELEGRAM_CHAT_ID = process.env.TELEGRAM_CHAT_ID || '';

export const ETHERSCAN_API_KEY_1 = process.env.ETHERSCAN_API_KEY_1 || '';
export const ETHERSCAN_API_KEY_2 = process.env.ETHERSCAN_API_KEY_2 || '';

/** Etherscan v2 API base URL and Celo chain id for txList. */
export const ETHERSCAN_V2_BASE_URL = 'https://api.etherscan.io/v2/api';
export const ETHERSCAN_CHAIN_ID_CELO = 42220;


export const FUNCTION_RUNTIME_OPTS: CallableOptions = {
  // timeoutSeconds: 60,
  // memory: "256MiB",
};

admin.initializeApp();

// Contract addresses
export const CREATE2_FACTORY = "0x4e59b44847b379578588920cA78FbF26c0B4956C" as Address;

// Canvassing contract addresses (proxies)
export const CANVASSING_WALLET_REGISTRY_PROXY_ADDRESS: Address = "0x28E9Ed54beDB75ce666E6a0921F4E79141c594d1";
export const CANVASSING_TASK_MANAGER_PROXY_ADDRESS: Address = "0x351df8260080CA47386442Bb19d4D025277bbAe3";
export const CANVASSING_REWARDER_PROXY_ADDRESS: Address = "0x351df8260080CA47386442Bb19d4D025277bbAe3";
export const CANVASSING_GAS_SPONSOR_PROXY_ADDRESS: Address = "0xBdA6e6b41a688eaB89C57d3DA3BF8b556B43AB2C";

// API endpoint configs
export const PIMLICO_URL = `https://api.pimlico.io/v2/42220/rpc?apikey=${PIMLICO_API_KEY}`;

export const DRPC_URL = `https://lb.drpc.live/celo/${DRPC_API_KEY}`;

export const REWARD_TOKEN_ADDRESS = "0x62B8B11039FcfE5aB0C56E502b1C372A3d2a9c7A" as Address;

export const PUBLIC_CLIENT = createPublicClient({
  chain: celo,
  transport: http(DRPC_URL),
});

export const PRIVY_CLIENT = new PrivyClient(PRIVY_APP_ID, PRIVY_APP_SECRET, {
  walletApi: {
    authorizationPrivateKey: PRIVY_WALLET_AUTH_PRIVATE_KEY,
  },
});

export const PAX_MASTER_PRIVATE_KEY_ACCOUNT = privateKeyToAccount(`0x${PAX_MASTER_PRIVATE_KEY}`);

export const DB = admin.firestore;

export const MESSAGING = admin.messaging();

export const AUTH = admin.auth();