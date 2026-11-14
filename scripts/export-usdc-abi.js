import fs from "fs";
const artifact = JSON.parse(fs.readFileSync("artifacts/contracts/LasavoUSDCPool.sol/LasavoUSDCPool.json", "utf-8"));
fs.writeFileSync("contracts/LasavoUSDCPoolABI.json", JSON.stringify(artifact.abi, null, 2));
console.log("Exported LasavoUSDCPool ABI with", artifact.abi.length, "methods/events");
