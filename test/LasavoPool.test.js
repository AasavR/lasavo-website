import { expect } from "chai";
import hre from "hardhat";

describe("LasavoSavingsPool On-Chain Verification", function () {
  let pool;
  let deployer, saver;

  before(async function () {
    [deployer, saver] = await hre.ethers.getSigners();
    const Factory = await hre.ethers.getContractFactory("LasavoSavingsPool");
    pool = await Factory.deploy();
    await pool.waitForDeployment();

    // Fund the pool reserve
    await deployer.sendTransaction({
      to: await pool.getAddress(),
      value: hre.ethers.parseEther("1.0")
    });
  });

  it("1. Verifies testnet transaction and micro-deposit succeeds", async function () {
    const microDeposit = hre.ethers.parseEther("0.0001");
    const tx = await pool.connect(saver).deposit({ value: microDeposit });
    await tx.wait();

    const summary = await pool.getAccountSummary(saver.address);
    expect(summary[0]).to.equal(microDeposit);
    expect(summary[3]).to.equal(1480n); // 14.8% APY
  });

  it("2. Verifies yield pool functions correctly and APY accrues over time", async function () {
    // Fast forward 30 days
    await hre.network.provider.send("evm_increaseTime", [30 * 24 * 3600]);
    await hre.network.provider.send("evm_mine");

    const summary = await pool.getAccountSummary(saver.address);
    const accruedYield = summary[1];
    expect(accruedYield).to.be.gt(0n);
    console.log("Accrued Yield over 30 days:", hre.ethers.formatEther(accruedYield), "ETH");
  });

  it("3. Verifies zero lockup instant withdrawal of principal + yield", async function () {
    const preBal = await hre.ethers.provider.getBalance(saver.address);
    const tx = await pool.connect(saver).withdrawAll();
    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const postBal = await hre.ethers.provider.getBalance(saver.address);
    expect(postBal + gasUsed).to.be.gt(preBal);
  });
});
