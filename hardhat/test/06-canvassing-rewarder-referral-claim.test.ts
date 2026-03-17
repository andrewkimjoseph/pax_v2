/**
 * CanvassingRewarder: claimReferralReward flow.
 * Deploys CanvassingRewarder + CanvassingWalletRegistry + MockERC20.
 * Registers the referred EO wallet, then claims a referral reward.
 */
import { expect } from "chai";
import hre from "hardhat";
import {
  type Hex,
  encodeFunctionData,
  createWalletClient,
  createPublicClient,
  custom,
  parseEther,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { hardhat } from "viem/chains";
import { erc1967ProxyABI } from "./abis/erc1967Proxy";
import { erc1967ByteCode } from "./bytecode/ERC1967";

const PK = [
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
] as const;

describe("6. CanvassingRewarder referral claim", function () {
  it("allows a referred participant to claim a referral reward", async function () {
    const provider = hre.network.provider;
    const transport = custom({
      async request({ method, params }) {
        return provider.send(method, params as unknown[]);
      },
    });
    const publicClient = createPublicClient({ chain: hardhat, transport });
    const ownerClient = createWalletClient({
      chain: hardhat,
      transport,
      account: privateKeyToAccount(PK[0]),
    });
    const smartAccountClient = createWalletClient({
      chain: hardhat,
      transport,
      account: privateKeyToAccount(PK[1]),
    });
    const referrerClient = createWalletClient({
      chain: hardhat,
      transport,
      account: privateKeyToAccount(PK[2]),
    });
    const referredClient = createWalletClient({
      chain: hardhat,
      transport,
      account: privateKeyToAccount(PK[3]),
    });

    const owner = ownerClient.account.address;
    const smartAccount = smartAccountClient.account.address;
    const referrerEo = referrerClient.account.address;
    const referredEo = referredClient.account.address;
    const signerAccount = privateKeyToAccount(PK[0]);
    const chainId = BigInt(hardhat.id);

    const taskManagerArtifact = await hre.artifacts.readArtifact("CanvassingTaskManager");
    const rewarderArtifact = await hre.artifacts.readArtifact("CanvassingRewarder");
    const registryArtifact = await hre.artifacts.readArtifact("CanvassingWalletRegistry");
    const mockErc20Artifact = await hre.artifacts.readArtifact("MockERC20");

    // Deploy TaskManager (required by CanvassingRewarder.initialize)
    const tmInit = encodeFunctionData({
      abi: taskManagerArtifact.abi,
      functionName: "initialize",
      args: [owner, signerAccount.address],
    });
    const tmImplHash = await ownerClient.deployContract({
      abi: taskManagerArtifact.abi,
      bytecode: taskManagerArtifact.bytecode as Hex,
    });
    const tmImplRcpt = await publicClient.waitForTransactionReceipt({ hash: tmImplHash });
    const tmProxyHash = await ownerClient.deployContract({
      abi: erc1967ProxyABI,
      bytecode: erc1967ByteCode as Hex,
      args: [tmImplRcpt.contractAddress!, tmInit],
    });
    const tmProxyRcpt = await publicClient.waitForTransactionReceipt({ hash: tmProxyHash });
    const taskManager = tmProxyRcpt.contractAddress!;

    // Deploy CanvassingRewarder
    const rewarderInit = encodeFunctionData({
      abi: rewarderArtifact.abi,
      functionName: "initialize",
      args: [owner, signerAccount.address, taskManager],
    });
    const rwImplHash = await ownerClient.deployContract({
      abi: rewarderArtifact.abi,
      bytecode: rewarderArtifact.bytecode as Hex,
    });
    const rwImplRcpt = await publicClient.waitForTransactionReceipt({ hash: rwImplHash });
    const rwProxyHash = await ownerClient.deployContract({
      abi: erc1967ProxyABI,
      bytecode: erc1967ByteCode as Hex,
      args: [rwImplRcpt.contractAddress!, rewarderInit],
    });
    const rwProxyRcpt = await publicClient.waitForTransactionReceipt({ hash: rwProxyHash });
    const rewarder = rwProxyRcpt.contractAddress!;

    // Deploy CanvassingWalletRegistry
    const regInit = encodeFunctionData({
      abi: registryArtifact.abi,
      functionName: "initialize",
      args: [owner],
    });
    const regImplHash = await ownerClient.deployContract({
      abi: registryArtifact.abi,
      bytecode: registryArtifact.bytecode as Hex,
    });
    const regImplRcpt = await publicClient.waitForTransactionReceipt({ hash: regImplHash });
    const regProxyHash = await ownerClient.deployContract({
      abi: erc1967ProxyABI,
      bytecode: erc1967ByteCode as Hex,
      args: [regImplRcpt.contractAddress!, regInit],
    });
    const regProxyRcpt = await publicClient.waitForTransactionReceipt({ hash: regProxyHash });
    const registry = regProxyRcpt.contractAddress!;

    // Set registry on rewarder
    await ownerClient.writeContract({
      address: rewarder,
      abi: rewarderArtifact.abi,
      functionName: "setRegistry",
      args: [registry],
    });

    // Register the referred EO wallet in the registry
    await ownerClient.writeContract({
      address: registry,
      abi: registryArtifact.abi,
      functionName: "logWallet",
      args: [referredEo, "uid-referred-1"],
    });

    const isLogged = await publicClient.readContract({
      address: registry,
      abi: registryArtifact.abi,
      functionName: "isWalletLogged",
      args: [referredEo],
    });
    expect(isLogged).to.equal(true);

    // Deploy MockERC20 and fund the rewarder
    const tokenHash = await ownerClient.deployContract({
      abi: mockErc20Artifact.abi,
      bytecode: mockErc20Artifact.bytecode as Hex,
      args: ["RewardToken", "RWD"],
    });
    const tokenRcpt = await publicClient.waitForTransactionReceipt({ hash: tokenHash });
    const token = tokenRcpt.contractAddress!;

    await ownerClient.writeContract({
      address: token,
      abi: mockErc20Artifact.abi,
      functionName: "mint",
      args: [rewarder, parseEther("10000")],
    });

    // Sign the referral reward request (backend signer)
    const referralId = "referral-abc-123";
    const nonce = 42n;
    const amount = parseEther("1000");

    const claimSig = await signerAccount.signTypedData({
      domain: {
        name: "CanvassingRewarder",
        version: "1",
        chainId,
        verifyingContract: rewarder,
      },
      types: {
        ReferralRewardRequest: [
          { name: "eoAddress", type: "address" },
          { name: "referredEoAddress", type: "address" },
          { name: "smartAccountContractAddress", type: "address" },
          { name: "recipientAddress", type: "address" },
          { name: "referralId", type: "string" },
          { name: "token", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "nonce", type: "uint256" },
        ],
      },
      primaryType: "ReferralRewardRequest",
      message: {
        eoAddress: referrerEo,
        referredEoAddress: referredEo,
        smartAccountContractAddress: smartAccount,
        recipientAddress: smartAccount,
        referralId,
        token,
        amount,
        nonce,
      },
    });

    // Claim the referral reward (msg.sender = smartAccount)
    await smartAccountClient.writeContract({
      address: rewarder,
      abi: rewarderArtifact.abi,
      functionName: "claimReferralReward",
      args: [
        referrerEo,
        referredEo,
        smartAccount,
        smartAccount,
        referralId,
        token,
        amount,
        nonce,
        claimSig,
      ],
    });

    // Verify token was transferred
    const bal = await publicClient.readContract({
      address: token,
      abi: mockErc20Artifact.abi,
      functionName: "balanceOf",
      args: [smartAccount],
    });
    expect(bal).to.equal(amount);

    // Verify on-chain state
    const rewarded = await publicClient.readContract({
      address: rewarder,
      abi: rewarderArtifact.abi,
      functionName: "checkIfReferralRewarded",
      args: [referralId, referrerEo, referredEo],
    });
    expect(rewarded).to.equal(true);

    const totalReferrals = await publicClient.readContract({
      address: rewarder,
      abi: rewarderArtifact.abi,
      functionName: "totalReferralRewards",
      args: [],
    });
    expect(totalReferrals).to.equal(1n);
  });

  it("rejects duplicate referral claims", async function () {
    const provider = hre.network.provider;
    const transport = custom({
      async request({ method, params }) {
        return provider.send(method, params as unknown[]);
      },
    });
    const publicClient = createPublicClient({ chain: hardhat, transport });
    const ownerClient = createWalletClient({
      chain: hardhat,
      transport,
      account: privateKeyToAccount(PK[0]),
    });
    const smartAccountClient = createWalletClient({
      chain: hardhat,
      transport,
      account: privateKeyToAccount(PK[1]),
    });
    const referrerClient = createWalletClient({
      chain: hardhat,
      transport,
      account: privateKeyToAccount(PK[2]),
    });
    const referredClient = createWalletClient({
      chain: hardhat,
      transport,
      account: privateKeyToAccount(PK[3]),
    });

    const owner = ownerClient.account.address;
    const smartAccount = smartAccountClient.account.address;
    const referrerEo = referrerClient.account.address;
    const referredEo = referredClient.account.address;
    const signerAccount = privateKeyToAccount(PK[0]);
    const chainId = BigInt(hardhat.id);

    const taskManagerArtifact = await hre.artifacts.readArtifact("CanvassingTaskManager");
    const rewarderArtifact = await hre.artifacts.readArtifact("CanvassingRewarder");
    const registryArtifact = await hre.artifacts.readArtifact("CanvassingWalletRegistry");
    const mockErc20Artifact = await hre.artifacts.readArtifact("MockERC20");

    // Deploy everything
    const tmInit = encodeFunctionData({
      abi: taskManagerArtifact.abi,
      functionName: "initialize",
      args: [owner, signerAccount.address],
    });
    const tmImplHash = await ownerClient.deployContract({
      abi: taskManagerArtifact.abi,
      bytecode: taskManagerArtifact.bytecode as Hex,
    });
    const tmImplRcpt = await publicClient.waitForTransactionReceipt({ hash: tmImplHash });
    const tmProxyHash = await ownerClient.deployContract({
      abi: erc1967ProxyABI,
      bytecode: erc1967ByteCode as Hex,
      args: [tmImplRcpt.contractAddress!, tmInit],
    });
    const tmProxyRcpt = await publicClient.waitForTransactionReceipt({ hash: tmProxyHash });
    const taskManager = tmProxyRcpt.contractAddress!;

    const rewarderInit = encodeFunctionData({
      abi: rewarderArtifact.abi,
      functionName: "initialize",
      args: [owner, signerAccount.address, taskManager],
    });
    const rwImplHash = await ownerClient.deployContract({
      abi: rewarderArtifact.abi,
      bytecode: rewarderArtifact.bytecode as Hex,
    });
    const rwImplRcpt = await publicClient.waitForTransactionReceipt({ hash: rwImplHash });
    const rwProxyHash = await ownerClient.deployContract({
      abi: erc1967ProxyABI,
      bytecode: erc1967ByteCode as Hex,
      args: [rwImplRcpt.contractAddress!, rewarderInit],
    });
    const rwProxyRcpt = await publicClient.waitForTransactionReceipt({ hash: rwProxyHash });
    const rewarder = rwProxyRcpt.contractAddress!;

    const regInit = encodeFunctionData({
      abi: registryArtifact.abi,
      functionName: "initialize",
      args: [owner],
    });
    const regImplHash = await ownerClient.deployContract({
      abi: registryArtifact.abi,
      bytecode: registryArtifact.bytecode as Hex,
    });
    const regImplRcpt = await publicClient.waitForTransactionReceipt({ hash: regImplHash });
    const regProxyHash = await ownerClient.deployContract({
      abi: erc1967ProxyABI,
      bytecode: erc1967ByteCode as Hex,
      args: [regImplRcpt.contractAddress!, regInit],
    });
    const regProxyRcpt = await publicClient.waitForTransactionReceipt({ hash: regProxyHash });
    const registry = regProxyRcpt.contractAddress!;

    await ownerClient.writeContract({
      address: rewarder,
      abi: rewarderArtifact.abi,
      functionName: "setRegistry",
      args: [registry],
    });

    await ownerClient.writeContract({
      address: registry,
      abi: registryArtifact.abi,
      functionName: "logWallet",
      args: [referredEo, "uid-referred-dup"],
    });

    const tokenHash = await ownerClient.deployContract({
      abi: mockErc20Artifact.abi,
      bytecode: mockErc20Artifact.bytecode as Hex,
      args: ["RewardToken", "RWD"],
    });
    const tokenRcpt = await publicClient.waitForTransactionReceipt({ hash: tokenHash });
    const token = tokenRcpt.contractAddress!;

    await ownerClient.writeContract({
      address: token,
      abi: mockErc20Artifact.abi,
      functionName: "mint",
      args: [rewarder, parseEther("10000")],
    });

    const referralId = "referral-dup-test";
    const amount = parseEther("1000");

    const sig1 = await signerAccount.signTypedData({
      domain: {
        name: "CanvassingRewarder",
        version: "1",
        chainId,
        verifyingContract: rewarder,
      },
      types: {
        ReferralRewardRequest: [
          { name: "eoAddress", type: "address" },
          { name: "referredEoAddress", type: "address" },
          { name: "smartAccountContractAddress", type: "address" },
          { name: "recipientAddress", type: "address" },
          { name: "referralId", type: "string" },
          { name: "token", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "nonce", type: "uint256" },
        ],
      },
      primaryType: "ReferralRewardRequest",
      message: {
        eoAddress: referrerEo,
        referredEoAddress: referredEo,
        smartAccountContractAddress: smartAccount,
        recipientAddress: smartAccount,
        referralId,
        token,
        amount,
        nonce: 1n,
      },
    });

    // First claim should succeed
    await smartAccountClient.writeContract({
      address: rewarder,
      abi: rewarderArtifact.abi,
      functionName: "claimReferralReward",
      args: [referrerEo, referredEo, smartAccount, smartAccount, referralId, token, amount, 1n, sig1],
    });

    // Second claim with a new signature should revert
    const sig2 = await signerAccount.signTypedData({
      domain: {
        name: "CanvassingRewarder",
        version: "1",
        chainId,
        verifyingContract: rewarder,
      },
      types: {
        ReferralRewardRequest: [
          { name: "eoAddress", type: "address" },
          { name: "referredEoAddress", type: "address" },
          { name: "smartAccountContractAddress", type: "address" },
          { name: "recipientAddress", type: "address" },
          { name: "referralId", type: "string" },
          { name: "token", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "nonce", type: "uint256" },
        ],
      },
      primaryType: "ReferralRewardRequest",
      message: {
        eoAddress: referrerEo,
        referredEoAddress: referredEo,
        smartAccountContractAddress: smartAccount,
        recipientAddress: smartAccount,
        referralId,
        token,
        amount,
        nonce: 2n,
      },
    });

    await expect(
      smartAccountClient.writeContract({
        address: rewarder,
        abi: rewarderArtifact.abi,
        functionName: "claimReferralReward",
        args: [referrerEo, referredEo, smartAccount, smartAccount, referralId, token, amount, 2n, sig2],
      })
    ).to.be.rejectedWith("referral reward already claimed");
  });
});
