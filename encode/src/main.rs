use std::{fs, path::Path};

use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct ArbitrageReq {
    init_amount: u128,
    min_profit: u128,
    swap_steps: Vec<SwapStep>,
}

#[derive(Debug, Deserialize)]
struct SwapStep {
    is_uniswap_v3: bool,
    sell_token1: bool,
    pool_addr: String,
}

/// TODO Eth pool address checksum
fn hex_to_20byte_array(hex_str: &str) -> [u8; 20] {
    let bytes =
        hex::decode(hex_str.strip_prefix("0x").unwrap_or(hex_str)).expect("Invalid hex string");
    let mut array = [0u8; 20];
    array.copy_from_slice(&bytes[..20]); // Ensure it's exactly 20 bytes
    array
}

/// TODO consider if there is alignment needing.
/// The total length of the data is 32+ several 22 bytes
/// Need to consider if there is needing for padding as 32+ several 32 bytes to make the data read and write more efficiency
/// The reason need to consider is, that longer data means more gas, so that is trade-off
pub fn encode_arbitrage_request(
    initial_amount: u128,
    min_profit: u128,
    steps: Vec<(bool, bool, [u8; 20])>,
) -> Vec<u8> {
    let mut encoded = Vec::new();

    // Encode the initial WETH amount (128 bits)
    encoded.extend_from_slice(&initial_amount.to_be_bytes());

    // Encode the minimum required profit in WETH (128 bits)
    encoded.extend_from_slice(&min_profit.to_be_bytes());

    // Encode each swap step
    for (is_v3, is_token1, pool) in steps {
        let mut selector: u8 = 0; // 1 byte (8 bits)

        if is_v3 {
            selector |= 0x80; // Set first bit (Uniswap V3)
        }
        if is_token1 {
            selector |= 0x40; // Set second bit (selling token1)
        }

        // Push selector byte
        encoded.push(selector);

        // Append the 160-bit pool address
        encoded.extend_from_slice(&pool);
    }

    encoded
}

/// TODO Use a configuration way to pass the path is better than input directly
/// Also add more tests for this Rust script. Now just apply the "arbitrage-test.js" to do the encoding
/// and trigger(test) the "AtomicArbitrage.sol" smart contract
/// and compare the encoded result with the printed encoded request below
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: cargo run -- <path_to_json_file>");
        std::process::exit(1);
    }
    let file_path = Path::new(&args[1]);
    let json_str = fs::read_to_string(file_path).expect("Failed to read JSON file");

    let arbitrage_req: ArbitrageReq = serde_json::from_str(&json_str).expect("Invalid JSON format");

    let steps: Vec<(bool, bool, [u8; 20])> = arbitrage_req
        .swap_steps
        .iter()
        .map(|step| {
            (
                step.is_uniswap_v3,
                step.sell_token1,
                hex_to_20byte_array(&step.pool_addr),
            )
        })
        .collect();
    let encoded =
        encode_arbitrage_request(arbitrage_req.init_amount, arbitrage_req.min_profit, steps);

    // Print encoded calldata in hex format
    println!("Encoded Data: 0x{}", hex::encode(encoded));
}
