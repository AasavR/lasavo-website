with open("index.html", "r", encoding="utf-8") as f:
    c = f.read()

# Update NETWORKS object with Base Mainnet & Monad Mainnet
old_net = """    const NETWORKS = {
      baseSepolia: {
        chainId: "0x14a34", // 84532
        chainName: "Base Sepolia",
        rpcUrls: ["https://sepolia.base.org"],
        nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 }
      },
      monadTestnet: {
        chainId: "0x279f", // 10143
        chainName: "Monad Testnet",
        rpcUrls: ["https://testnet-rpc.monad.xyz"],
        nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 }
      }
    };"""

new_net = """    const NETWORKS = {
      baseMainnet: {
        chainId: "0x2105", // 8453
        chainName: "Base Mainnet",
        rpcUrls: ["https://mainnet.base.org"],
        nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
        blockExplorerUrls: ["https://basescan.org"],
        isMainnet: true
      },
      monadMainnet: {
        chainId: "0x8f", // 143
        chainName: "Monad Mainnet",
        rpcUrls: ["https://rpc.monad.xyz"],
        nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
        blockExplorerUrls: ["https://monadscan.com"],
        isMainnet: true
      },
      baseSepolia: {
        chainId: "0x14a34", // 84532
        chainName: "Base Sepolia (Testnet)",
        rpcUrls: ["https://sepolia.base.org"],
        nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
        blockExplorerUrls: ["https://sepolia.basescan.org"],
        isMainnet: false
      },
      monadTestnet: {
        chainId: "0x279f", // 10143
        chainName: "Monad Testnet",
        rpcUrls: ["https://testnet-rpc.monad.xyz"],
        nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
        blockExplorerUrls: ["https://testnet.monadexplorer.com"],
        isMainnet: false
      }
    };"""

if old_net in c:
    c = c.replace(old_net, new_net)
    print("Replaced NETWORKS definition")
else:
    print("NETWORKS string not matched exactly")

with open("index.html", "w", encoding="utf-8") as f:
    f.write(c)
print("Updated index.html")
