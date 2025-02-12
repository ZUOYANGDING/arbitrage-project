// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./AtomicArbitrage.sol";

contract MockUniswapV2Pool {
    IERC20 public token;
    address public arbitrageContract;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external {
        require(to != address(0), "Invalid recipient");

        uint256 swapAmount = amount0Out > 0 ? amount0Out : amount1Out;

        // Transfer tokens to recipient
        token.transfer(to, swapAmount);

        AtomicArbitrage(to).uniswapV2Call(
            msg.sender,
            amount0Out,
            amount1Out,
            data
        );
    }

    function token0() external view returns (address) {
        return address(token);
    }

    function token1() external view returns (address) {
        return address(token);
    }
}
