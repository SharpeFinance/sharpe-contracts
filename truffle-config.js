const HDWalletProvider = require('@truffle/hdwallet-provider');
const fs = require('fs');
const mnemonic = fs.readFileSync(".secret").toString().trim();

require('chai/register-should');

module.exports = {
  // Uncommenting the defaults below
  // provides for an easier quick-start with Ganache.
  // You can also follow this format for other networks;
  // see <http://truffleframework.com/docs/advanced/configuration>
  // for more details on how to specify configuration options!
  //
  networks: {
      testnet: {
        provider: () => new HDWalletProvider(mnemonic, `https://data-seed-prebsc-1-s1.binance.org:8545`),
        network_id: 97,
        // confirmations: 10,
        // timeoutBlocks: 200,
        // skipDryRun: true
      },
  //  development: {
  //    host: "127.0.0.1",
  //    port: 7545,
  //    network_id: "*"
  //  },
  //  test: {
  //    host: "127.0.0.1",
  //    port: 7545,
  //    network_id: "*"
  //  }
  },
  //
  compilers: {
    solc: {
      version: "0.6.12",
      settings: {
        "optimizer": {
          "enabled": true,
          "runs": 200
        }
      }
    }
  },

  mocha: {
    timeout: 12000000
  }
};
