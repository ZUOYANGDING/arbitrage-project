### This is Project in a Hardhat framework

### Structure
- In directory `contract`:
  - `AtomicArbitrage.sol` is smart contract to do the MEV
  - Other 3 smart contracts are for testing
- In directory `encode`
  - `src/main.rs` is the script to do the request encoding
  - `test.json` is for encoding test
- In directory `test`
  - `arbitrage-test.js` is for smart contract testing
- `hardhat.config.js` is for testing
- Directory/file not included:
  - "scripts" include the smart contract deploy code
  - "test" in encode for Rust code testing (can be done in future)

### Run
Test the smart contract by folk ETH to local by Alchemy API

- Change the api-key part in `hardhat.config.js` to be your own Alchemy API
- Start the forked chain
    ```bash
    npx hardhat node
    ```
- Run the `arbitrage-test.js`
    ```
    npx hardhat test --network localhost
    ```
- For the Encoding, go to `encode` directory, use the logging result above to edit the `test.json`:
    ```
    cargo run test.json
    ```
  Compare the loggin result above with the printed result by rust code

