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
    uint256 public minProfit;

    struct SwapStep {
        bool isV3; // True if Uniswap V3, false if Uniswap V2
        bool isToken1; // True if selling token1, false if selling token0
        address pool; // Address of the liquidity pool
    }

    constructor(address _weth) {
        WETH = _weth;
        owner = msg.sender;
    }

    function executeArbitrage(bytes calldata data) external {
        require(msg.sender == owner, "Only owner can execute");
        // console.log(" Owner verified");

        // console.log("Raw Calldata:", data.length);

        uint256 initialAmount;
        assembly {
            let amounts := calldataload(data.offset) // Read first 32 bytes
            initialAmount := shr(128, amounts) // Shift right to extract first 128 bits
            sstore(
                minProfit.slot,
                and(amounts, 0xffffffffffffffffffffffffffffffff)
            ) // Mask last 128 bits
        }

        // console.log("Initial Amount Decoded (Assembly):", initialAmount);
        // console.log("Min Profit Decoded (Assembly):", minProfit);

        require(minProfit > 0, "minProfit must be set");

        uint256 offset = 32;
        uint256 stepIndex = 0;
        SwapStep[] memory steps = new SwapStep[]((data.length - 32) / 21);

        while (offset < data.length) {
            // console.log(" Loop Iteration Start, Offset:", offset);

            (bool isV3, bool isToken1, address pool) = decodeStep(data, offset);

            // console.log("Step Decoded - isV3:", isV3);
            // console.log("Step Decoded - isToken1:", isToken1);
            // console.log("Step Decoded - Pool:", pool);

            steps[stepIndex] = SwapStep(isV3, isToken1, pool);
            stepIndex++;
            offset += 21;

            // console.log(" Loop Iteration End, New Offset:", offset);
        }

        // console.log(" All Steps Decoded, Total Steps:", stepIndex);

        // Start first flash swap
        if (steps[0].isV3) {
            _flashV3(steps[0].pool, initialAmount, steps[0].isToken1);
        } else {
            _flashV2(steps[0].pool, initialAmount, steps[0].isToken1);
        }
    }

    function _flashV2(address pool, uint256 amount, bool isToken1) internal {
        console.log("In flash V2");
        IUniswapV2Pair(pool).swap(
            isToken1 ? 0 : amount,
            isToken1 ? amount : 0,
            address(this),
            ""
        );
    }

    function _flashV3(address pool, uint256 amount, bool isToken1) internal {
        IUniswapV3Pool(pool).swap(
            address(this),
            isToken1,
            int256(amount),
            isToken1 ? type(uint160).max : 0,
            ""
        );
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata /* data */
    ) external {
        require(sender == address(this), "Not authorized");
        _executeSwaps(amount0 > 0 ? amount0 : amount1);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external {
        _executeSwaps(uint256(amount0Delta > 0 ? amount0Delta : amount1Delta));
    }

    function _executeSwaps(uint256 amount) internal {
        uint256 profit;
        // console.log("amount", amount);
        if (amount >= minProfit) {
            unchecked {
                profit = amount - minProfit;
            }
        } else {
            revert("Not enough profit");
        }

        // Transfer profit to owner
        IERC20(WETH).transfer(owner, amount);
    }

    function decodeStep(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (bool, bool, address) {
        bool isV3 = (uint8(data[offset]) & 0x80) != 0;
        bool isToken1 = (uint8(data[offset]) & 0x40) != 0;

        address pool;
        assembly {
            let poolData := calldataload(add(data.offset, add(offset, 1)))
            pool := and(
                shr(96, poolData),
                0xffffffffffffffffffffffffffffffffffffffff
            )
        }

        // console.log("Decoded Step - isV3:", isV3);
        // console.log("Decoded Step - isToken1:", isToken1);
        // console.log("Decoded Pool Address:", pool);

        return (isV3, isToken1, pool);
    }
}
