const { expect } = require("chai");
const { ethers } = require("hardhat");


// TODO more testing could be written
// s.a result of the balance after the trading (check not just log out)
// Also apply the test with real eath testnet instead of folk and run at local
describe("AtomicArbitrage", function () {
    let arbitrage, owner, user;
    let WETH, MockV2Pool, MockV3Pool;
    let initialAmount = ethers.parseEther("1"); // 1 ETH in wei
    let minProfit = ethers.parseEther("0.001"); // 0.001 ETH profit in wei

    // Helper function to encode uint128 values correctly (16 bytes)
    function toUint128Hex(value) {
        return ethers.zeroPadValue(ethers.toBeHex(value), 16);
    }

    // Helper function to manually encode swap steps correctly
    function encodeSwapStep(isV3, isToken1, poolAddress) {
        // Convert `isV3` and `isToken1` into 1 byte (8 bits)
        let selectorByte = (isV3 ? 0x80 : 0x00) | (isToken1 ? 0x40 : 0x00);

        // Convert `poolAddress` to a 20-byte (160-bit) hex string
        let poolAddressHex = ethers.zeroPadValue(poolAddress, 20).slice(2); // Remove '0x' prefix

        return ethers.toBeHex(selectorByte, 1) + poolAddressHex;
    }

    beforeEach(async function () {
        [owner, user] = await ethers.getSigners();

        const WETHFactory = await ethers.getContractFactory("MockWETH");
        WETH = await WETHFactory.deploy();
        await WETH.waitForDeployment();

        console.log("WETH Deployed At:", WETH.target);

        const MockV2PoolFactory = await ethers.getContractFactory("MockUniswapV2Pool");
        MockV2Pool = await MockV2PoolFactory.deploy(WETH.target);
        await MockV2Pool.waitForDeployment();

        console.log("MockUniswapV2Pool Deployed At:", MockV2Pool.target);

        const MockV3PoolFactory = await ethers.getContractFactory("MockUniswapV3Pool");
        MockV3Pool = await MockV3PoolFactory.deploy(WETH.target);
        await MockV3Pool.waitForDeployment();

        console.log("MockUniswapV3Pool Deployed At:", MockV3Pool.target);

        const ArbitrageFactory = await ethers.getContractFactory("AtomicArbitrage");
        arbitrage = await ArbitrageFactory.deploy(WETH.target);
        await arbitrage.waitForDeployment();

        console.log("AtomicArbitrage Deployed At:", arbitrage.target);

        let codeV2 = await ethers.provider.getCode(MockV2Pool.target);
        let codeV3 = await ethers.provider.getCode(MockV3Pool.target);

        console.log("MockV2Pool Code Size:", codeV2.length);
        console.log("MockV3Pool Code Size:", codeV3.length);

        if (codeV2.length <= 2 || codeV3.length <= 2) {
            throw new Error("One of the mock pools is not deployed correctly!");
        }

        // Get ETH balance before deposit
        const balanceETH = await ethers.provider.getBalance(owner.address);
        console.log("ETH Balance Before Deposit:", ethers.formatEther(balanceETH));

        // Deposit ETH into WETH
        const depositTx = await WETH.connect(owner).deposit({ value: ethers.parseEther("10") });
        await depositTx.wait(); // Wait for confirmation

        // Verify WETH balance after deposit
        const balanceWETH = await WETH.balanceOf(owner.address);
        console.log("WETH Balance After Deposit:", ethers.formatEther(balanceWETH));

        await WETH.connect(owner).transfer(MockV2Pool.target, ethers.parseEther("2"));
        console.log("WETH Balance (MockV2Pool):", ethers.formatEther(await WETH.balanceOf(MockV2Pool.target)));

        await WETH.connect(owner).transfer(MockV3Pool.target, ethers.parseEther("2"));
        console.log("WETH Balance (MockV3Pool):", ethers.formatEther(await WETH.balanceOf(MockV3Pool.target)));

        await WETH.connect(owner).transfer(arbitrage.target, ethers.parseEther("1"));
        console.log("WETH Balance (Arbitrage Contract):", ethers.formatEther(await WETH.balanceOf(arbitrage.target)));
    });

    it("Should execute arbitrage successfully and transfer profit to owner", async function () {
        console.log("MockV2Pool Address:", MockV2Pool.target);
        console.log("MockV3Pool Address:", MockV3Pool.target);
        console.log("Arbitrage Contract Address:", arbitrage.target);

        // Manually pack the calldata correctly
        const encodedAmounts = toUint128Hex(initialAmount) + toUint128Hex(minProfit).slice(2);

        // Manually encode each swap step
        const encodedStep1 = encodeSwapStep(false, false, MockV2Pool.target); // Uniswap V2 swap
        const encodedStep2 = encodeSwapStep(true, true, MockV3Pool.target);   // Uniswap V3 swap

        // Combine everything into final calldata
        const swapSteps = "0x" + encodedAmounts.slice(2) + encodedStep1.slice(2) + encodedStep2.slice(2);

        console.log("Encoded Arbitrage Call Data:", swapSteps);

        try {
            console.log("Executing Arbitrage...");
            let tx = await arbitrage.connect(owner).executeArbitrage(swapSteps);
            await tx.wait();
        } catch (error) {
            console.log("Transaction Error:", error);
        }

        let finalBalance = await WETH.balanceOf(owner.address);
        console.log("Final WETH Balance:", finalBalance.toString());

        expect(finalBalance).to.be.gte(minProfit);
    });

    it("Should revert if profit is less than minProfit", async function () {
        let highMinProfit = ethers.parseEther("5"); // Set minProfit higher than possible profits

        console.log("Using minProfit:", highMinProfit.toString());

        // Manually pack incorrect data for failure test
        const encodedAmounts = toUint128Hex(initialAmount) + toUint128Hex(highMinProfit).slice(2);

        const encodedStep1 = encodeSwapStep(false, false, MockV2Pool.target);
        const encodedStep2 = encodeSwapStep(true, true, MockV3Pool.target);

        const swapSteps = "0x" + encodedAmounts.slice(2) + encodedStep1.slice(2) + encodedStep2.slice(2);

        console.log("Encoded Arbitrage Call Data:", swapSteps);

        await expect(arbitrage.connect(owner).executeArbitrage(swapSteps))
            .to.be.revertedWith("Not enough profit");
    });
});
