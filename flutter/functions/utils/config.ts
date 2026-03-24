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

export const FUNCTION_RUNTIME_OPTS: CallableOptions = {
  // enforceAppCheck: true
};

admin.initializeApp();

// Contract addresses
export const CREATE2_FACTORY = "0x4e59b44847b379578588920cA78FbF26c0B4956C" as Address;

// Identity / whitelist contract (used for UBI reminders)
export const IDENTITY_PROXY_CONTRACT_ADDRESS =
  "0xC361A6E67822a0EDc17D899227dd9FC50BD62F42" as Address;

// Canvassing contract addresses (proxies)
export const CANVASSING_WALLET_REGISTRY_PROXY_ADDRESS: Address = "0x74Cc10C7c8EE72CbAB508f3A6142C90c68579f3F"; //Implm - 0x531b2AD505Efe7f24A9FEB74931F544aFfDeA69A
export const CANVASSING_GAS_SPONSOR_PROXY_ADDRESS: Address = "0xBdA6e6b41a688eaB89C57d3DA3BF8b556B43AB2C"; // Implm - 0xE6570E2DD6A24f48092Ae4c9F60012Efd87CEcB7
export const CANVASSING_TASK_MANAGER_PROXY_ADDRESS: Address = "0x339a7328289ef6f51be3f4d0Cb19cc46EB9eF4f1"; // Implm - 0xed1c55593C82E13E3D7bbF39bCAa3071eE76Fc12
export const CANVASSING_REWARDER_PROXY_ADDRESS: Address = "0x4D167933D742B31229bc730eADf5f2E3c4feceA2"; // Implm - 0xEdC0D00857962893c0BD69AFd65C1E3A99F6f6dC

// API endpoint configs
export const PIMLICO_URL = `https://api.pimlico.io/v2/42220/rpc?apikey=${PIMLICO_API_KEY}`;

export const DRPC_URL = `https://lb.drpc.live/celo/${DRPC_API_KEY}`;

export const GOOD_DOLLAR_TOKEN_ADDRESS = "0x62B8B11039FcfE5aB0C56E502b1C372A3d2a9c7A" as Address;
export const USDM_TOKEN_ADDRESS = "0x765de816845861e75a25fca122bb6898b8b1282a" as Address;
export const USDT_TOKEN_ADDRESS = "0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e" as Address;
export const USDC_TOKEN_ADDRESS = "0xcebA9300f2b948710d2653dD7B07f33A8B32118C" as Address;

/** Default CELO amount to sponsor per wallet (in ether). */
export const DEFAULT_SPONSOR_AMOUNT_CELO = "0.05";

/** Default referral reward amount (off-chain, stored as numeric). */
export const REFERRAL_REWARD_AMOUNT = 1000;

/** Minimum donation amount in G$ for GoodCollective donations. */
export const MIN_DONATION_AMOUNT_GD = 100;

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