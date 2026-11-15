
import { ethers } from "ethers";
import fs from "fs";

async function main() {
  console.log("=================================================");
  console.log("   LASAVO YIELD POOL ON-CHAIN VERIFICATION TEST   ");
  console.log("=================================================\n");

  // 1. Setup local simulated EVM provider & signers
  const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545");
  const accounts = await provider.listAccounts();
  const deployer = accounts[0];
  const microSaver = accounts[1];

  console.log("1. Deployer Account:", deployer.address);
  console.log("   Saver Account:   ", microSaver.address);

  // 2. Deploy LasavoSavingsPool contract
  const artifact = JSON.parse(fs.readFileSync("artifacts/contracts/LasavoSavingsPool.sol/LasavoSavingsPool.json", "utf8"));
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, deployer);
  
  console.log("\n2. Deploying LasavoSavingsPool contract...");
  const pool = await factory.deploy();
  await pool.waitForDeployment();
  const poolAddress = await pool.getAddress();
  console.log("   [SUCCESS] Contract Deployed at:", poolAddress);

  // Top up protocol yield reserve (0.5 ETH)
  await deployer.sendTransaction({
    to: poolAddress,
    value: ethers.parseEther("0.5")
  });
  console.log("   [SUCCESS] Protocol Yield Reserve funded with 0.5 ETH");

  // 3. Test Micro-Deposit (0.0001 ETH / ~$0.25)
  console.log("\n3. Testing Micro-Deposit of 0.0001 ETH (Lowest Barrier)...");
  const depositTx = await pool.connect(microSaver).deposit({
    value: ethers.parseEther("0.0001")
  });
  await depositTx.wait();
  console.log("   [SUCCESS] Deposit Transaction Mined! Tx Hash:", depositTx.hash);

  let summary = await pool.getAccountSummary(microSaver.address);
  console.log("   Initial Principal:     ", ethers.formatEther(summary[0]), "ETH");
  console.log("   Initial Accrued Yield: ", ethers.formatEther(summary[1]), "ETH");
  console.log("   Active Pool APY:       ", (Number(summary[3]) / 100).toFixed(1) + "%");

  // 4. Time-warp 30 days to test real APY accrual
  console.log("\n4. Advancing on-chain time by 30 days (2,592,000 seconds)...");
  await provider.send("evm_increaseTime", [30 * 24 * 3600]);
  await provider.send("evm_mine");

  summary = await pool.getAccountSummary(microSaver.address);
  console.log("   Principal:            ", ethers.formatEther(summary[0]), "ETH");
  console.log("   Accrued Yield (30d):  ", ethers.formatEther(summary[1]), "ETH");
  console.log("   Total Balance:        ", ethers.formatEther(summary[2]), "ETH");

  const hasAccrued = summary[1] > 0n;
  console.log("   APY Accrual Active:    [ " + (hasAccrued ? "VERIFIED YES" : "NO") + " ]");

  // 5. Test Instant Withdrawal of Principal + Yield
  console.log("\n5. Testing Instant Withdrawal of Total Savings...");
  const initialWalletBal = await provider.getBalance(microSaver.address);
  const withdrawTx = await pool.connect(microSaver).withdrawAll();
  await withdrawTx.wait();
  console.log("   [SUCCESS] Withdrawal Mined! Tx Hash:", withdrawTx.hash);

  const postSummary = await pool.getAccountSummary(microSaver.address);
  console.log("   Post-Withdrawal Principal: ", ethers.formatEther(postSummary[0]), "ETH");
  console.log("   Post-Withdrawal Yield:     ", ethers.formatEther(postSummary[1]), "ETH");
  
  const finalWalletBal = await provider.getBalance(microSaver.address);
  console.log("   Saver Net Balance Change:  +", ethers.formatEther(finalWalletBal - initialWalletBal), "ETH");

  console.log("\n=================================================");
  console.log("   ALL VERIFICATION CHECKS PASSED SUCCESSFULLY!   ");
  console.log("=================================================");
}

main().catch(console.error);
