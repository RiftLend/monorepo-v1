// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {ILendingPoolAddressesProvider} from "../src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "../src/interfaces/ILendingPoolConfigurator.sol";

import {MockERC20} from "../lib/forge-std/src/mocks/MockERC20.sol";
import {SuperchainAsset} from "../src/SuperchainAsset.sol";
import {AToken} from "../src/tokenization/AToken.sol";
import {StableDebtToken} from "../src/tokenization/StableDebtToken.sol";
import {VariableDebtToken} from "../src/tokenization/VariableDebtToken.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {LendingPoolAddressesProvider} from "../src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "../src/LendingPoolConfigurator.sol";
import {DefaultReserveInterestRateStrategy} from "../src/DefaultReserveInterestRateStrategy.sol";

contract baseTest is Test {

    // chains
    uint256 public opMainnet;
    uint256 public base;

    // participants
    address public owner = vm.addr(1000);
    address public alice = vm.addr(1);
    address public pool_Admin = vm.addr(500);

    // markets
    string public marketId;

    // assets
    MockERC20 public INR;
    SuperchainAsset public superchainAsset;
    AToken public aTokenImpl;
    StableDebtToken public stabledebtTokenImpl;
    VariableDebtToken public variabledebtTokenImpl;

    // system contracts
    LendingPoolAddressesProvider public lpAddressProvider;
    LendingPoolConfigurator public lpConfigurator;
    LendingPoolConfigurator public proxyConfigurator;
    DefaultReserveInterestRateStrategy public strategy;
    LendingPool public implementationLp;
    LendingPool public proxyLp ;

    function setUp() public {
        vm.label(alice, 'alice');
        vm.label(owner, 'owner');
        vm.label(pool_Admin, 'pool_Admin');

        _configureOpMainnet();
        _configureBase();

    }

    function _configureOpMainnet() internal {
        opMainnet = vm.createSelectFork("https://mainnet.optimism.io/");
        
        // assets ------------------------------------------------------------
        // INR
        INR = new MockERC20(); 
        INR.initialize("Mock rupee","INR",18);
        vm.label(address(INR), "INR");

        // implementation aToken
        aTokenImpl = new AToken();
        
        // implementation stabledebtToken
        stabledebtTokenImpl = new StableDebtToken();
        
        // implementation variabledebtToekn
        variabledebtTokenImpl = new VariableDebtToken();

        // lendingPoolAddressProvider
        lpAddressProvider = new LendingPoolAddressesProvider("INR",owner,owner);
        vm.label(address(lpAddressProvider), "lpAddressProvider");
        
        // superchainAsset for opMainnet
        superchainAsset = new SuperchainAsset("superchainAsset","SCA",18,address(INR),ILendingPoolAddressesProvider(address(lpAddressProvider)),owner);
        vm.label(address(superchainAsset), "superchainAsset");

        // implementation LendingPool
        implementationLp = new LendingPool();
        vm.label(address(implementationLp), "implementationLp");

        // proxy LendingPool
        vm.prank(owner);
        lpAddressProvider.setLendingPoolImpl(address(implementationLp));
        proxyLp = LendingPool(lpAddressProvider.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        // settings in addressProvider
        vm.prank(owner);
        lpAddressProvider.setPoolAdmin(owner);

        // implementation configurator
        lpConfigurator = new LendingPoolConfigurator();

        // proxy configurator
        vm.prank(owner);
        lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

        // strategy
        strategy = new DefaultReserveInterestRateStrategy(ILendingPoolAddressesProvider(address(lpAddressProvider)),1,2,3,4,5,6);

    }

    function _configureBase() internal {
        base = vm.createSelectFork("https://mainnet.base.org");
        
        // INR
        INR = new MockERC20(); 
        INR.initialize("Mock rupee","INR",18);
        vm.label(address(INR), "INR");

        // implementation aToken
        aTokenImpl = new AToken();
        
        // implementation stabledebtToken
        stabledebtTokenImpl = new StableDebtToken();
        
        // implementation variabledebtToekn
        variabledebtTokenImpl = new VariableDebtToken();

        // lendingPoolAddressProvider
        lpAddressProvider = new LendingPoolAddressesProvider("INR",owner,owner);
        vm.label(address(lpAddressProvider), "lpAddressProvider");
        
        // superchainAsset for opMainnet
        superchainAsset = new SuperchainAsset("superchainAsset","SCA",18,address(INR),ILendingPoolAddressesProvider(address(lpAddressProvider)),owner);
        vm.label(address(superchainAsset), "superchainAsset");

        // implementation LendingPool
        implementationLp = new LendingPool();
        vm.label(address(implementationLp), "implementationLp");

        // proxy LendingPool
        vm.prank(owner);
        lpAddressProvider.setLendingPoolImpl(address(implementationLp));
        proxyLp = LendingPool(lpAddressProvider.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        // settings in addressProvider
        vm.prank(owner);
        lpAddressProvider.setPoolAdmin(owner);

        // implementation configurator
        lpConfigurator = new LendingPoolConfigurator();

        // proxy configurator
        vm.prank(owner);
        lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

        // strategy
        strategy = new DefaultReserveInterestRateStrategy(ILendingPoolAddressesProvider(address(lpAddressProvider)),1,2,3,4,5,6);

    }
}

contract LendingPoolTest is baseTest {

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