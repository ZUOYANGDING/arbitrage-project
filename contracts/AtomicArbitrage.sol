// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

// Interface for Wrapped Ether (WETH)
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 amount) external returns (bool);
}

contract AtomicArbitrage {
    address immutable WETH; // Address of the WETH contract
    address owner; // Contract owner

    // Header data: first 128 bits is the initial WETH input,
    // next 128 bits is the minimum required profit.
    uint256 public arbitrageInitialAmount;
    uint256 public minProfit;

    // Store the first pool address to know where to repay the flash swap.
    address public firstPoolAddress;

    // Full payload (header + swap steps) stored in state.
    bytes public arbitragePayload;
    uint256 public totalSteps;
    uint256 public currentStep;

    struct SwapStep {
        bool isV3; // True if Uniswap V3, false if Uniswap V2.
        bool isToken1; // True if the swap sells token1, false if token0.
        address pool; // Address of the liquidity pool.
    }

    constructor(address _weth) {
        WETH = _weth;
        owner = msg.sender;
    }

    /// @notice Initiates the arbitrage by decoding the payload, storing it,
    ///         and starting the first flash swap.
    /// @param data The encoded arbitrage request:
    /// - First 32 bytes: header (16 bytes initialAmount, 16 bytes minProfit)
    /// - Each subsequent 21 bytes represent one swap step.
    function executeArbitrage(bytes calldata data) external {
        require(msg.sender == owner, "Only owner can execute");
        require(data.length >= 32, "Data too short");

        // Store the full payload in state.
        arbitragePayload = data;

        // Create a memory copy of the calldata for decoding.
        bytes memory dataMem = data;

        // Decode header: first 32 bytes.
        uint256 initialAmount;
        assembly {
            let amounts := mload(add(dataMem, 32))
            initialAmount := shr(128, amounts)
            sstore(
                minProfit.slot,
                and(amounts, 0xffffffffffffffffffffffffffffffff)
            )
        }
        require(initialAmount > 0, "Initial amount must be > 0");
        require(minProfit > 0, "minProfit must be set");

        arbitrageInitialAmount = initialAmount;

        // Calculate total swap steps (each step is 21 bytes after the header).
        totalSteps = (dataMem.length - 32) / 21;
        require(totalSteps > 0, "No swap steps provided");

        currentStep = 0;
        uint256 offset = 32; // The first step starts immediately after the header.

        // Decode the first swap step.
        (bool isV3, bool isToken1, address pool) = decodeStep(dataMem, offset);
        // Save the first pool so we know whom to repay.
        firstPoolAddress = pool;
        if (isV3) {
            _flashV3(pool, initialAmount, isToken1);
        } else {
            _flashV2(pool, initialAmount, isToken1);
        }
    }

    /// @notice Initiates a flash swap on a Uniswap V2 pool.
    function _flashV2(address pool, uint256 amount, bool isToken1) internal {
        console.log("Flash swap on V2 pool:", pool, "amount:", amount);
        IUniswapV2Pair(pool).swap(
            isToken1 ? 0 : amount,
            isToken1 ? amount : 0,
            address(this),
            ""
        );
    }

    /// @notice Initiates a flash swap on a Uniswap V3 pool.
    function _flashV3(address pool, uint256 amount, bool isToken1) internal {
        console.log("Flash swap on V3 pool:", pool, "amount:", amount);
        IUniswapV3Pool(pool).swap(
            address(this),
            isToken1, // Direction flag.
            int256(amount),
            isToken1 ? type(uint160).max : 0,
            ""
        );
    }

    /// @notice Callback for Uniswap V2 flash swaps.
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata /* data */
    ) external {
        require(sender == address(this), "Not authorized");
        uint256 received = amount0 > 0 ? amount0 : amount1;
        _processNextSwap(received);
    }

    /// @notice Callback for Uniswap V3 flash swaps.
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /* data */
    ) external {
        uint256 received = uint256(
            amount0Delta > 0 ? amount0Delta : amount1Delta
        );
        _processNextSwap(received);
    }

    /// @notice Proceeds to the next swap hop, or finalizes the arbitrage if done.
    function _processNextSwap(uint256 amount) internal {
        console.log("current step", currentStep);
        currentStep++;
        if (currentStep < totalSteps) {
            uint256 offset = 32 + currentStep * 21;
            // Convert the stored payload to memory for decoding.
            bytes memory payload = arbitragePayload;
            (bool isV3, bool isToken1, address pool) = decodeStep(
                payload,
                offset
            );
            if (isV3) {
                _flashV3(pool, amount, isToken1);
            } else {
                _flashV2(pool, amount, isToken1);
            }
        } else {
            _finalize(amount);
        }
    }

    /// @notice Finalizes the arbitrage by checking that profit meets expectations,
    ///         then transfers the resulting WETH to the owner.
    function _finalize(uint256 amount) internal {
        console.log("amount: ", amount);
        console.log("arbitrageInitailAmount: ", arbitrageInitialAmount);
        console.log("minProfit: ", minProfit);
        require(
            amount >= arbitrageInitialAmount + minProfit,
            "Not enough profit"
        );
        uint256 profit = amount - arbitrageInitialAmount;
        console.log("Arbitrage successful, profit:", profit);
        // Repay the borrowed amount to the first pool.
        require(
            IERC20(WETH).transfer(firstPoolAddress, arbitrageInitialAmount),
            "Repayment failed"
        );
        // Transfer the entire final profit to the owner.
        require(IERC20(WETH).transfer(owner, profit), "Transfer failed");
        console.log("finalized success");
    }

    /// @notice Decodes one arbitrage hop from the payload.
    /// @param data The payload in memory.
    /// @param offset The offset at which the swap step begins.
    /// @return isV3 True if the swap is on a Uniswap V3 pool.
    /// @return isToken1 True if the swap sells token1.
    /// @return pool The address of the liquidity pool.
    function decodeStep(
        bytes memory data,
        uint256 offset
    ) internal pure returns (bool isV3, bool isToken1, address pool) {
        uint8 flags = uint8(data[offset]);
        isV3 = (flags & 0x80) != 0;
        isToken1 = (flags & 0x40) != 0;
        // The next 20 bytes represent the pool address.
        assembly {
            let poolData := mload(add(add(data, 32), add(offset, 1)))
            pool := and(
                shr(96, poolData),
                0xffffffffffffffffffffffffffffffffffffffff
            )
        }
    }
}
