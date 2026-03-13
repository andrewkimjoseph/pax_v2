/**
 * CanvassingTaskManager + CanvassingRewarder: screen smart account, then claimTaskReward from EOA.
 * Uses Hardhat's in-process provider (no separate JSON-RPC server).
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
] as const;

describe("5. CanvassingRewarder task claim (screen then claim)", function () {
  it("allows claim after screening smart account (EOA != smart account)", async function () {
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
    const eoClient = createWalletClient({
      chain: hardhat,
      transport,
      account: privateKeyToAccount(PK[2]),
    });
    const owner = ownerClient.account.address;
    const smartAccount = smartAccountClient.account.address;
    const eoAddress = eoClient.account.address;
    const signerAccount = privateKeyToAccount(PK[0]);

    const taskManagerArtifact = await hre.artifacts.readArtifact("CanvassingTaskManager");
    const rewarderArtifact = await hre.artifacts.readArtifact("CanvassingRewarder");
    const mockErc20Artifact = await hre.artifacts.readArtifact("MockERC20");

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
    const tmImplAddress = tmImplRcpt.contractAddress!;

    const tmProxyHash = await ownerClient.deployContract({
      abi: erc1967ProxyABI,
      bytecode: erc1967ByteCode as Hex,
      args: [tmImplAddress, tmInit],
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
    const rwImplAddress = rwImplRcpt.contractAddress!;

    const rwProxyHash = await ownerClient.deployContract({
      abi: erc1967ProxyABI,
      bytecode: erc1967ByteCode as Hex,
      args: [rwImplAddress, rewarderInit],
    });
    const rwProxyRcpt = await publicClient.waitForTransactionReceipt({ hash: rwProxyHash });
    const rewarder = rwProxyRcpt.contractAddress!;

    const tokenHash = await ownerClient.deployContract({
      abi: mockErc20Artifact.abi,
      bytecode: mockErc20Artifact.bytecode as Hex,
      args: ["T", "T"],
    });
    const tokenRcpt = await publicClient.waitForTransactionReceipt({ hash: tokenHash });
    const token = tokenRcpt.contractAddress!;

    await ownerClient.writeContract({
      address: token,
      abi: mockErc20Artifact.abi,
      functionName: "mint",
      args: [rewarder, parseEther("100")],
    });

    const taskId = "task-1";
    const screeningNonce = 1n;
    const chainId = BigInt(hardhat.id);

    const screeningSig = await signerAccount.signTypedData({
      domain: {
        name: "CanvassingTaskManager",
        version: "1",
        chainId,
        verifyingContract: taskManager,
      },
      types: {
        ScreeningRequest: [
          { name: "smartAccountContractAddress", type: "address" },
          { name: "taskId", type: "string" },
          { name: "nonce", type: "uint256" },
        ],
      },
      primaryType: "ScreeningRequest",
      message: {
        smartAccountContractAddress: smartAccount,
        taskId,
        nonce: screeningNonce,
      },
    });

    await smartAccountClient.writeContract({
      address: taskManager,
      abi: taskManagerArtifact.abi,
      functionName: "screenParticipantProxy",
      args: [smartAccount, taskId, screeningNonce, screeningSig],
    });

    const screened = await publicClient.readContract({
      address: taskManager,
      abi: taskManagerArtifact.abi,
      functionName: "checkIfScreened",
      args: [taskId, smartAccount],
    });
    expect(screened).to.equal(true);

    const claimNonce = 2n;
    const amount = parseEther("10");
    const claimSig = await signerAccount.signTypedData({
      domain: {
        name: "CanvassingRewarder",
        version: "1",
        chainId,
        verifyingContract: rewarder,
      },
      types: {
        TaskRewardRequest: [
          { name: "eoAddress", type: "address" },
          { name: "smartAccountContractAddress", type: "address" },
          { name: "recipientAddress", type: "address" },
          { name: "taskId", type: "string" },
          { name: "token", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "nonce", type: "uint256" },
        ],
      },
      primaryType: "TaskRewardRequest",
      message: {
        eoAddress,
        smartAccountContractAddress: smartAccount,
        recipientAddress: smartAccount,
        taskId,
        token,
        amount,
        nonce: claimNonce,
      },
    });

    await smartAccountClient.writeContract({
      address: rewarder,
      abi: rewarderArtifact.abi,
      functionName: "claimTaskReward",
      args: [
        eoAddress,
        smartAccount,
        smartAccount,
        taskId,
        token,
        amount,
        claimNonce,
        claimSig,
      ],
    });

    const bal = await publicClient.readContract({
      address: token,
      abi: mockErc20Artifact.abi,
      functionName: "balanceOf",
      args: [smartAccount],
    });
    expect(bal).to.equal(amount);
  });
});
