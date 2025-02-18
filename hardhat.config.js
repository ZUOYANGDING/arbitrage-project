require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: "0.8.20",
  networks: {
    hardhat: { // Local Testnet
      forking: {
        url: "https://eth-sepolia.g.alchemy.com/v2/MY_ALCHEMY_API_KEY", // Fork mainnet
      },
    },
    localhost: { // Connect tests to running Hardhat node
      url: "http://127.0.0.1:8545",
    }
  },
};
