// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./Base.t.sol";
contract LendingPoolTest is BaseTest {

    function testDeposit() public {
        // arrange
        vm.selectFork(opMainnet);

        ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
        input[0].aTokenImpl = address(aTokenImpl);
        input[0].stableDebtTokenImpl = address(stabledebtTokenImpl);
        input[0].variableDebtTokenImpl = address(variabledebtTokenImpl);
        input[0].underlyingAssetDecimals = 18;
        input[0].interestRateStrategyAddress = address(strategy);
        input[0].underlyingAsset = address(INR);
        input[0].treasury = vm.addr(35);
        input[0].incentivesController = vm.addr(17);
        input[0].superchainAsset = address(superchainAsset);
        input[0].underlyingAssetName = "Mock rupee";
        input[0].aTokenName = "aToken-INR";
        input[0].aTokenSymbol = "aINR";
        input[0].variableDebtTokenName = "vDebt";
        input[0].variableDebtTokenSymbol = "vDBT";
        input[0].stableDebtTokenName = "vStable";
        input[0].stableDebtTokenSymbol = "vSBT";
        input[0].params = "v";
        input[0].salt = "salt";
        vm.prank(owner);
        proxyConfigurator.batchInitReserve(input);

        // act
        address asset = address(INR);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        address onBehalfOf = alice;
        uint16 referralCode = 0;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 1;

        vm.prank(alice);
        proxyLp.deposit(asset, amounts, onBehalfOf, referralCode, chainIds);

        // assert
        // 1. superchainAsset
        address aToken_ = proxyLp.getReserveData(asset).aTokenAddress;
        address superchainAsset_ = proxyLp.getReserveData(asset).superchainAssetAddress;
        assertEq(SuperchainAsset(superchainAsset_).balanceOf(aToken_), 1000);

        // 2. aToken
        // assertEq((aToken).balanceOf(alice), 1000);
        // assertEq((aToken).balanceOf(treasury), 10);

    }   
}
