export default {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    baseMainnet: {
      type: "http",
      url: "https://mainnet.base.org",
      chainId: 8453,
    },
    monadMainnet: {
      type: "http",
      url: "https://rpc.monad.xyz",
      chainId: 143,
    },
    baseSepolia: {
      type: "http",
      url: "https://sepolia.base.org",
      chainId: 84532,
    },
    monadTestnet: {
      type: "http",
      url: "https://testnet-rpc.monad.xyz",
      chainId: 10143,
    },
  },
};
