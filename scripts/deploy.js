import fs from "fs";
import { ethers } from "ethers";

const keyData = JSON.parse(fs.readFileSync(".deployer.json", "utf-8"));
const artifact = JSON.parse(fs.readFileSync("artifacts/contracts/LasavoSavingsPool.sol/LasavoSavingsPool.json", "utf-8"));

async function deployTo(networkName, rpcUrl, chainId) {
  console.log(`\n--- Attempting deployment to ${networkName} (Chain ID: ${chainId}) ---`);
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(keyData.privateKey, provider);
    const balance = await provider.getBalance(wallet.address);
    console.log(`Deployer address: ${wallet.address}`);
    console.log(`Current Balance: ${ethers.formatEther(balance)}`);

    if (balance === 0n) {
      console.log(`Note: Deployer has 0 balance on ${networkName}. Waiting for testnet faucet drop.`);
      return null;
    }

    const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
    console.log("Deploying contract...");
    const contract = await factory.deploy();
    await contract.waitForDeployment();
    const addr = await contract.getAddress();
    console.log(`SUCCESS! LasavoSavingsPool deployed to ${networkName} at: ${addr}`);
    return addr;
  } catch (err) {
    console.log(`Deployment note on ${networkName}:`, err.message);
    return null;
  }
}

async function main() {
  await deployTo("Base Sepolia", "https://sepolia.base.org", 84532);
  await deployTo("Monad Testnet", "https://testnet-rpc.monad.xyz", 10143);
}

main();
