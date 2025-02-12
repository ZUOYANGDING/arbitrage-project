// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./AtomicArbitrage.sol";

contract MockUniswapV3Pool {
    IERC20 public token;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function swap(
        address recipient,
        bool /*isToken1*/,
        int256 amountSpecified,
        uint160 /*sqrtPriceLimitX96*/,
        bytes calldata data
    ) external {
        require(recipient != address(0), "Invalid recipient");

        uint256 amount = uint256(
            amountSpecified > 0 ? amountSpecified : -amountSpecified
        );

        // Transfer the tokens to the recipient
        token.transfer(recipient, amount);

        AtomicArbitrage(recipient).uniswapV3SwapCallback(
            int256(amount),
            0,
            data
        );
    }

    function token0() external view returns (address) {
        return address(token);
    }

    function token1() external view returns (address) {
        return address(token);
    }

    function fee() external pure returns (uint24) {
        return 3000; // Mock 0.3% Uniswap V3 fee
    }
}
