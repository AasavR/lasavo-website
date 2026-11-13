import fs from "fs";
import { ethers } from "ethers";

// 1. Generate or load a dedicated Lasavo testnet deployer wallet
const keyPath = ".deployer.json";
let wallet;

if (fs.existsSync(keyPath)) {
  const data = JSON.parse(fs.readFileSync(keyPath, "utf-8"));
  wallet = new ethers.Wallet(data.privateKey);
} else {
  wallet = ethers.Wallet.createRandom();
  fs.writeFileSync(keyPath, JSON.stringify({
    address: wallet.address,
    privateKey: wallet.privateKey
  }, null, 2));
}

console.log("=== Lasavo Testnet Deployer Wallet ===");
console.log("Address:", wallet.address);
console.log("======================================");

// 2. Check balance on Base Sepolia
const baseSepoliaRpc = "https://sepolia.base.org";
const providerBase = new ethers.JsonRpcProvider(baseSepoliaRpc);
const baseBal = await providerBase.getBalance(wallet.address);
console.log("Base Sepolia Balance:", ethers.formatEther(baseBal), "ETH");

// 3. Check balance on Monad Testnet
const monadRpc = "https://testnet-rpc.monad.xyz";
try {
  const providerMonad = new ethers.JsonRpcProvider(monadRpc);
  const monadBal = await providerMonad.getBalance(wallet.address);
  console.log("Monad Testnet Balance:", ethers.formatEther(monadBal), "MON");
} catch (e) {
  console.log("Monad RPC check note:", e.message);
}
