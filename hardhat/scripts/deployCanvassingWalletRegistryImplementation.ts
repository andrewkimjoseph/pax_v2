import hre from "hardhat";
import { config as loadEnv } from "dotenv";
import {
  type Hex,
  createPublicClient,
  createWalletClient,
  http,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { celo } from "viem/chains";

loadEnv();

async function main() {
  const rawPk = process.env.PAX_MASTER_PK;
  if (!rawPk) {
    throw new Error("PAX_MASTER_PK not found in environment variables");
  }

  const infuraApiKey = process.env.INFURA_API_KEY;
  if (!infuraApiKey) {
    throw new Error("INFURA_API_KEY not found in environment variables");
  }

  const account = privateKeyToAccount(
    (rawPk.startsWith("0x") ? rawPk : `0x${rawPk}`) as Hex
  );
  const rpcUrl = `https://celo-mainnet.infura.io/v3/${infuraApiKey}`;
  const publicClient = createPublicClient({
    chain: celo,
    transport: http(rpcUrl),
  });
  const walletClient = createWalletClient({
    chain: celo,
    transport: http(rpcUrl),
    account,
  });

  console.log(`Deployer: ${account.address}`);
  console.log(`Network: celo (${celo.id.toString()})`);

  const artifact = await hre.artifacts.readArtifact("CanvassingWalletRegistry");
  const txHash = await walletClient.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode as Hex,
    args: [],
  });
  console.log(`Deployment tx: ${txHash}`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  const implementationAddress = receipt.contractAddress;
  if (!implementationAddress) {
    throw new Error("Deployment receipt did not include contractAddress");
  }

  console.log(
    `CanvassingWalletRegistry implementation deployed at: ${implementationAddress}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
