import fs from "fs";
import { ethers } from "ethers";

const artifact = JSON.parse(fs.readFileSync("artifacts/contracts/LasavoSavingsPool.sol/LasavoSavingsPool.json", "utf-8"));
fs.writeFileSync("contracts/LasavoSavingsPoolABI.json", JSON.stringify(artifact.abi, null, 2));
console.log("ABI exported successfully:", artifact.abi.length, "items");
