// src/utils/rewardSignatures.ts
import {
  Address,
  Hex,
  verifyTypedData,
} from "viem";
import { celo } from "viem/chains";
import { createViemAccount } from "@privy-io/server-auth/viem";
import { randomBytes } from "crypto";
import { logger } from "firebase-functions/v2";
import { PRIVY_CLIENT, PAX_MASTER_PRIVATE_KEY_ACCOUNT } from "../../utils/config";

// Generate a random nonce for signatures
export function generateRandomNonce(): bigint {
  // Use crypto.randomBytes to generate cryptographically strong random values
  const randomBytes32 = randomBytes(32);
  
  // Convert to hexadecimal string and then to BigInt
  const randomHex = randomBytes32.toString('hex');
  return BigInt(`0x${randomHex}`);
}

// ---------------------------------------------------------------------------
// CanvassingRewarder — EIP-712 TaskRewardRequest
// Domain: name = "CanvassingRewarder", version = "1"
// Types: TaskRewardRequest(..., recipientAddress, taskId, ...)
// ---------------------------------------------------------------------------

type TaskRewardRequestTypes = {
  EIP712Domain: [
    { name: 'name'; type: 'string' },
    { name: 'version'; type: 'string' },
    { name: 'chainId'; type: 'uint256' },
    { name: 'verifyingContract'; type: 'address' }
  ];
  TaskRewardRequest: [
    { name: 'eoAddress'; type: 'address' },
    { name: 'smartAccountContractAddress'; type: 'address' },
    { name: 'recipientAddress'; type: 'address' },
    { name: 'taskId'; type: 'string' },
    { name: 'token'; type: 'address' },
    { name: 'amount'; type: 'uint256' },
    { name: 'nonce'; type: 'uint256' }
  ];
};

const createCanvassingRewarderDomain = (rewarderAddress: Address) => ({
  name: 'CanvassingRewarder' as const,
  version: '1' as const,
  chainId: BigInt(celo.id),
  verifyingContract: rewarderAddress,
});

export async function signTaskRewardRequestCanvassing(
  rewarderContractAddress: Address,
  eoAddress: Address,
  smartAccountContractAddress: Address,
  recipientAddress: Address,
  taskId: string,
  token: Address,
  amount: bigint,
  nonce: bigint
): Promise<Hex> {
  const domain = createCanvassingRewarderDomain(rewarderContractAddress);
  const types: TaskRewardRequestTypes = {
    EIP712Domain: [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' }
    ],
    TaskRewardRequest: [
      { name: 'eoAddress', type: 'address' },
      { name: 'smartAccountContractAddress', type: 'address' },
      { name: 'recipientAddress', type: 'address' },
      { name: 'taskId', type: 'string' },
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'nonce', type: 'uint256' }
    ]
  };
  const message = {
    eoAddress,
    smartAccountContractAddress,
    recipientAddress,
    taskId,
    token,
    amount,
    nonce,
  };
  return PAX_MASTER_PRIVATE_KEY_ACCOUNT.signTypedData({
    domain,
    types,
    primaryType: 'TaskRewardRequest',
    message,
  });
}

export async function createTaskRewardClaimSignaturePackageCanvassing(
  rewarderContractAddress: Address,
  eoAddress: Address,
  smartAccountContractAddress: Address,
  recipientAddress: Address,
  taskId: string,
  token: Address,
  amount: bigint,
  nonce: bigint
) {
  const signature = await signTaskRewardRequestCanvassing(
    rewarderContractAddress,
    eoAddress,
    smartAccountContractAddress,
    recipientAddress,
    taskId,
    token,
    amount,
    nonce
  );
  const domain = createCanvassingRewarderDomain(rewarderContractAddress);
  const types: TaskRewardRequestTypes = {
    EIP712Domain: [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' }
    ],
    TaskRewardRequest: [
      { name: 'eoAddress', type: 'address' },
      { name: 'smartAccountContractAddress', type: 'address' },
      { name: 'recipientAddress', type: 'address' },
      { name: 'taskId', type: 'string' },
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'nonce', type: 'uint256' }
    ]
  };
  const message = {
    eoAddress,
    smartAccountContractAddress,
    recipientAddress,
    taskId,
    token,
    amount,
    nonce,
  };
  const isValid = await verifyTypedData({
    address: PAX_MASTER_PRIVATE_KEY_ACCOUNT.address,
    domain,
    types,
    primaryType: 'TaskRewardRequest',
    message,
    signature,
  });
  return {
    signature,
    isValid,
    nonce: nonce.toString(),
  };
}

// ---------------------------------------------------------------------------
// CanvassingRewarder — EIP-712 AchievementRewardRequest
// Types: AchievementRewardRequest(address eoAddress, address smartAccountContractAddress, string achievementId, address token, uint256 amount, uint256 nonce)
// ---------------------------------------------------------------------------

type AchievementRewardRequestTypes = {
  EIP712Domain: [
    { name: 'name'; type: 'string' },
    { name: 'version'; type: 'string' },
    { name: 'chainId'; type: 'uint256' },
    { name: 'verifyingContract'; type: 'address' }
  ];
  AchievementRewardRequest: [
    { name: 'eoAddress'; type: 'address' },
    { name: 'smartAccountContractAddress'; type: 'address' },
    { name: 'recipientAddress'; type: 'address' },
    { name: 'achievementId'; type: 'string' },
    { name: 'token'; type: 'address' },
    { name: 'amount'; type: 'uint256' },
    { name: 'nonce'; type: 'uint256' }
  ];
};

export async function signAchievementRewardRequestCanvassing(
  rewarderContractAddress: Address,
  eoAddress: Address,
  smartAccountContractAddress: Address,
  recipientAddress: Address,
  achievementId: string,
  token: Address,
  amount: bigint,
  nonce: bigint
): Promise<Hex> {
  const domain = createCanvassingRewarderDomain(rewarderContractAddress);
  const types: AchievementRewardRequestTypes = {
    EIP712Domain: [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' }
    ],
    AchievementRewardRequest: [
      { name: 'eoAddress', type: 'address' },
      { name: 'smartAccountContractAddress', type: 'address' },
      { name: 'recipientAddress', type: 'address' },
      { name: 'achievementId', type: 'string' },
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'nonce', type: 'uint256' }
    ]
  };
  const message = {
    eoAddress,
    smartAccountContractAddress,
    recipientAddress,
    achievementId,
    token,
    amount,
    nonce,
  };
  return PAX_MASTER_PRIVATE_KEY_ACCOUNT.signTypedData({
    domain,
    types,
    primaryType: 'AchievementRewardRequest',
    message,
  });
}

export async function createAchievementRewardClaimSignaturePackageCanvassing(
  rewarderContractAddress: Address,
  eoAddress: Address,
  smartAccountContractAddress: Address,
  recipientAddress: Address,
  achievementId: string,
  token: Address,
  amount: bigint,
  nonce: bigint
) {
  const signature = await signAchievementRewardRequestCanvassing(
    rewarderContractAddress,
    eoAddress,
    smartAccountContractAddress,
    recipientAddress,
    achievementId,
    token,
    amount,
    nonce
  );
  const domain = createCanvassingRewarderDomain(rewarderContractAddress);
  const types: AchievementRewardRequestTypes = {
    EIP712Domain: [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' }
    ],
    AchievementRewardRequest: [
      { name: 'eoAddress', type: 'address' },
      { name: 'smartAccountContractAddress', type: 'address' },
      { name: 'recipientAddress', type: 'address' },
      { name: 'achievementId', type: 'string' },
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'nonce', type: 'uint256' }
    ]
  };
  const message = {
    eoAddress,
    smartAccountContractAddress,
    recipientAddress,
    achievementId,
    token,
    amount,
    nonce,
  };
  const isValid = await verifyTypedData({
    address: PAX_MASTER_PRIVATE_KEY_ACCOUNT.address,
    domain,
    types,
    primaryType: 'AchievementRewardRequest',
    message,
    signature,
  });
  return {
    signature,
    isValid,
    nonce: nonce.toString(),
  };
}

// Define the types for reward claim requests
type RewardClaimRequestTypes = {
  EIP712Domain: [
    { name: 'name'; type: 'string' },
    { name: 'version'; type: 'string' },
    { name: 'chainId'; type: 'uint256' },
    { name: 'verifyingContract'; type: 'address' }
  ];
  RewardClaimRequest: [
    { name: 'participant'; type: 'address' },
    { name: 'taskCompletionId'; type: 'string' },
    { name: 'nonce'; type: 'uint256' }
  ];
};

// Define a concrete domain type with required fields
type TaskManagerDomain = {
  name: string;
  version: string;
  chainId: bigint;
  verifyingContract: Address;
};

// Create a domain object for EIP-712 signatures
const createDomain = (contractAddress: Address): TaskManagerDomain => ({
  name: 'TaskManager',
  version: '1',
  chainId: BigInt(celo.id),
  verifyingContract: contractAddress
});

/**
 * Sign a reward claim request using EIP-712 typed data
 * @param taskMasterServerWalletId The wallet ID of the task master
 * @param taskMasterServerWalletAddress The wallet address of the task master
 * @param taskManagerContractAddress TaskManager contract address
 * @param participantProxy Address of the participant proxy claiming the reward
 * @param taskCompletionId Task completion linked to the reward to be claimed
 * @param nonce Random value to prevent replay attacks
 * @returns Promise containing the signature
 */
export async function signRewardClaimRequest(
  taskMasterServerWalletId: string,
  taskMasterServerWalletAddress: Address,
  taskManagerContractAddress: Address,
  participantProxy: Address,
  taskCompletionId: string,
  nonce: bigint
): Promise<Hex> {
  // Create viem account from Privy wallet
  const signerAccount = await createViemAccount({
    walletId: taskMasterServerWalletId,
    address: taskMasterServerWalletAddress,
    privy: PRIVY_CLIENT,
  });

  const types: RewardClaimRequestTypes = {
    EIP712Domain: [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' }
    ],
    RewardClaimRequest: [
      { name: 'participant', type: 'address' },
      { name: 'taskCompletionId', type: 'string' },
      { name: 'nonce', type: 'uint256' }
    ]
  };
  
  const domain = createDomain(taskManagerContractAddress);
  
  const message = {
    participant: participantProxy,
    taskCompletionId,
    nonce
  };

  return signerAccount.signTypedData({
    domain,
    types,
    primaryType: 'RewardClaimRequest',
    message
  });
}

/**
 * Verify that a reward claim signature is valid and was signed by the expected signer
 * @param taskManagerContractAddress TaskManager contract address
 * @param participantProxy Address of the participant proxy claiming the reward
 * @param taskCompletionId Task completion linked to the reward to be claimed
 * @param nonce Random value to prevent replay attacks
 * @param signature The signature to verify
 * @param expectedSigner The address that should have signed the message
 * @returns Promise resolving to true if the signature is valid, false otherwise
 */
export async function verifyRewardClaimSignature(
  taskManagerContractAddress: Address,
  participantProxy: Address,
  taskCompletionId: string,
  nonce: bigint,
  signature: Hex,
  expectedSigner: Address
): Promise<boolean> {
  try {
    const types: RewardClaimRequestTypes = {
      EIP712Domain: [
        { name: 'name', type: 'string' },
        { name: 'version', type: 'string' },
        { name: 'chainId', type: 'uint256' },
        { name: 'verifyingContract', type: 'address' }
      ],
      RewardClaimRequest: [
        { name: 'participant', type: 'address' },
        { name: 'taskCompletionId', type: 'string' },
        { name: 'nonce', type: 'uint256' }
      ]
    };
    
    const domain = createDomain(taskManagerContractAddress);
    
    const message = {
      participant: participantProxy,
      taskCompletionId,
      nonce
    };

    return await verifyTypedData({
      address: expectedSigner,
      domain,
      types,
      primaryType: 'RewardClaimRequest',
      message,
      signature
    });
  } catch (error) {
    logger.error("[V1] Signature verification error:", error);
    return false;
  }
}

/**
 * Create a complete reward claim signature package for a participant proxy
 * @param taskManagerContractAddress TaskManager contract address
 * @param taskMasterServerWalletId ID of the task master server wallet
 * @param taskMasterServerWalletAddress Address of the task master server wallet
 * @param participantProxy Address of the participant proxy claiming the reward
 * @param taskCompletionId Task completion linked to the reward to be claimed
 * @param nonce Random nonce
 * @returns Object containing all necessary signature data
 */
export async function createRewardClaimSignaturePackage(
  taskManagerContractAddress: Address,
  taskMasterServerWalletId: string,
  taskMasterServerWalletAddress: Address,
  participantProxy: Address,
  taskCompletionId: string,
  nonce: bigint
) {
  const signature = await signRewardClaimRequest(
    taskMasterServerWalletId,
    taskMasterServerWalletAddress,
    taskManagerContractAddress,
    participantProxy,
    taskCompletionId,
    nonce
  );
  
  const isValid = await verifyRewardClaimSignature(
    taskManagerContractAddress,
    participantProxy,
    taskCompletionId,
    nonce,
    signature,
    taskMasterServerWalletAddress
  );
  
  return {
    signature,
    isValid,
    participantProxy,
    taskCompletionId,
    nonce: nonce.toString(),
  };
}