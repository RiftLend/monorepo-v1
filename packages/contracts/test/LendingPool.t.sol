// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {ILendingPoolAddressesProvider} from "../src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "../src/interfaces/ILendingPoolConfigurator.sol";

import {MockERC20} from "../src/tokenization/MockERC20.sol";
import {SuperchainAsset} from "../src/SuperchainAsset.sol";
import {AToken} from "../src/tokenization/AToken.sol";
import {StableDebtToken} from "../src/tokenization/StableDebtToken.sol";
import {VariableDebtToken} from "../src/tokenization/VariableDebtToken.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {LendingPoolAddressesProvider} from "../src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "../src/LendingPoolConfigurator.sol";
import {DefaultReserveInterestRateStrategy} from "../src/DefaultReserveInterestRateStrategy.sol";
import {LendingRateOracle} from "../src/LendingRateOracle.sol";

contract baseTest is Test {

    // chains
    uint256 public opMainnet;
    uint256 public base;

    // participants
    address public owner = vm.addr(1000);
    address public admin;
    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    // markets
    string public marketId;

    // assets
    MockERC20 public Underlying;
    SuperchainAsset public superchainAsset;
    AToken public aTokenImpl;
    StableDebtToken public stabledebtTokenImpl;
    VariableDebtToken public variabledebtTokenImpl;

    // system contracts
    LendingPoolAddressesProvider public lpAddressProvider;
    LendingPoolConfigurator public lpConfigurator;
    LendingPoolConfigurator public proxyConfigurator;
    DefaultReserveInterestRateStrategy public strategy;
    LendingRateOracle public oracle;
    LendingPool public implementationLp;
    LendingPool public proxyLp ;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        vm.label(admin, 'admin');
        vm.label(owner, 'owner');
        vm.label(alice, 'alice');

        _configureOpMainnet();
        _configureBase();

    }

    function _configureOpMainnet() internal {
        opMainnet = vm.createSelectFork("https://mainnet.optimism.io/");
        
        // Underlying
        Underlying = new MockERC20("Mock rupee","Underlying"); 
        vm.label(address(Underlying), "Underlying");
        Underlying.mint(alice, 1000_000);

        // implementation aToken
        aTokenImpl = new AToken();
        
        // implementation stabledebtToken
        stabledebtTokenImpl = new StableDebtToken();
        
        // implementation variabledebtToekn
        variabledebtTokenImpl = new VariableDebtToken();

        // lendingPoolAddressProvider
        lpAddressProvider = new LendingPoolAddressesProvider("Underlying",owner,owner);
        vm.label(address(lpAddressProvider), "lpAddressProvider");
        
        // superchainAsset for opMainnet
        superchainAsset = new SuperchainAsset("superchainAsset","SCA",18,address(Underlying),ILendingPoolAddressesProvider(address(lpAddressProvider)),owner);
        vm.label(address(superchainAsset), "superchainAsset");

        // implementation LendingPool
        implementationLp = new LendingPool();
        vm.label(address(implementationLp), "implementationLp");

        // admin
        vm.prank(owner);
        proxyAdmin = new ProxyAdmin();
        admin = address(proxyAdmin);
        
        // proxy LendingPool
        vm.prank(owner);
        lpAddressProvider.setLendingPoolImpl(address(implementationLp));
        proxyLp = LendingPool(lpAddressProvider.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        // settings in addressProvider
        vm.prank(owner);
        lpAddressProvider.setPoolAdmin(admin);

        // implementation configurator
        lpConfigurator = new LendingPoolConfigurator();

        // proxy configurator
        vm.prank(owner);
        lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

        // strategy
        strategy = new DefaultReserveInterestRateStrategy(ILendingPoolAddressesProvider(address(lpAddressProvider)),1,2,3,4,5,6);

        // lendingRateOracle
        oracle = new LendingRateOracle();
        vm.prank(owner);
        lpAddressProvider.setLendingRateOracle(address(oracle));
    }

    function _configureBase() internal {
        base = vm.createSelectFork("https://mainnet.base.org");
        
        // Underlying
        Underlying = new MockERC20("Mock rupee","Underlying"); 
        vm.label(address(Underlying), "Underlying");
        Underlying.mint(alice, 1000_000);

        // implementation aToken
        aTokenImpl = new AToken();
        
        // implementation stabledebtToken
        stabledebtTokenImpl = new StableDebtToken();
        
        // implementation variabledebtToekn
        variabledebtTokenImpl = new VariableDebtToken();

        // lendingPoolAddressProvider
        lpAddressProvider = new LendingPoolAddressesProvider("Underlying",owner,owner);
        vm.label(address(lpAddressProvider), "lpAddressProvider");
        
        // superchainAsset for opMainnet
        superchainAsset = new SuperchainAsset("superchainAsset","SCA",18,address(Underlying),ILendingPoolAddressesProvider(address(lpAddressProvider)),owner);
        vm.label(address(superchainAsset), "superchainAsset");

        // implementation LendingPool
        implementationLp = new LendingPool();
        vm.label(address(implementationLp), "implementationLp");

        // admin
        vm.prank(owner);
        proxyAdmin = new ProxyAdmin();
        admin = address(proxyAdmin);

        // proxy LendingPool
        vm.prank(owner);
        lpAddressProvider.setLendingPoolImpl(address(implementationLp));
        proxyLp = LendingPool(lpAddressProvider.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        // settings in addressProvider
        vm.prank(owner);
        lpAddressProvider.setPoolAdmin(admin);

        // implementation configurator
        lpConfigurator = new LendingPoolConfigurator();

        // proxy configurator
        vm.prank(owner);
        lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

        // strategy
        strategy = new DefaultReserveInterestRateStrategy(ILendingPoolAddressesProvider(address(lpAddressProvider)),1,2,3,4,5,6);

        // lendingRateOracle
        oracle = new LendingRateOracle();
        vm.prank(owner);
        lpAddressProvider.setLendingRateOracle(address(oracle));

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
        input[0].underlyingAsset = address(Underlying);
        input[0].treasury = vm.addr(35);
        input[0].incentivesController = vm.addr(17);
        input[0].superchainAsset = address(superchainAsset);
        input[0].underlyingAssetName = "Mock rupee";
        input[0].aTokenName = "aToken-Underlying";
        input[0].aTokenSymbol = "aUnderlying";
        input[0].variableDebtTokenName = "vDebt";
        input[0].variableDebtTokenSymbol = "vDBT";
        input[0].stableDebtTokenName = "vStable";
        input[0].stableDebtTokenSymbol = "vSBT";
        input[0].params = "v";
        input[0].salt = "salt";
        vm.prank(admin);
        proxyConfigurator.batchInitReserve(input);

        vm.prank(alice);
        Underlying.approve(address(proxyLp),1000);

        // act
        address asset = address(Underlying);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        address onBehalfOf = alice;
        uint16 referralCode = 0;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;

        vm.prank(alice);
        proxyLp.deposit(asset, amounts, onBehalfOf, referralCode, chainIds);

        // assert
        address superchainAsset_ = proxyLp.getReserveData(asset).superchainAssetAddress;
        address aToken_ = proxyLp.getReserveData(asset).aTokenAddress;
        // 1. underlying
        assertEq(MockERC20(asset).balanceOf(superchainAsset_), 1000);

        // 2. superchainAsset
        assertEq(SuperchainAsset(superchainAsset_).balanceOf(aToken_), 1000);

        // 3. aToken
        assertEq(AToken(aToken_).balanceOf(alice), 1000);

    }   

    function testDepositCrossChain() public {

    }

    function testWithdraw() public {
        // arrange
        vm.selectFork(opMainnet);

        ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
        input[0].aTokenImpl = address(aTokenImpl);
        input[0].stableDebtTokenImpl = address(stabledebtTokenImpl);
        input[0].variableDebtTokenImpl = address(variabledebtTokenImpl);
        input[0].underlyingAssetDecimals = 18;
        input[0].interestRateStrategyAddress = address(strategy);
        input[0].underlyingAsset = address(Underlying);
        input[0].treasury = vm.addr(35);
        input[0].incentivesController = vm.addr(17);
        input[0].superchainAsset = address(superchainAsset);
        input[0].underlyingAssetName = "Mock rupee";
        input[0].aTokenName = "aToken-Underlying";
        input[0].aTokenSymbol = "aUnderlying";
        input[0].variableDebtTokenName = "vDebt";
        input[0].variableDebtTokenSymbol = "vDBT";
        input[0].stableDebtTokenName = "vStable";
        input[0].stableDebtTokenSymbol = "vSBT";
        input[0].params = "v";
        input[0].salt = "salt";
        vm.prank(admin);
        proxyConfigurator.batchInitReserve(input);

        vm.prank(alice);
        Underlying.approve(address(proxyLp),1000);

        address asset = address(Underlying);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        address onBehalfOf = alice;
        uint16 referralCode = 0;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;

        vm.prank(alice);
        proxyLp.deposit(asset, amounts, onBehalfOf, referralCode, chainIds);        

        // act
        address asset_ = address(Underlying);
        uint256[] memory amounts_ = new uint256[](1);
        amounts_[0] = 800;
        address to_ = alice;
        uint256 toChainId_ = block.chainid;
        uint256[] memory chainIds_ = new uint256[](1);
        chainIds_[0] = block.chainid;

        vm.prank(alice);
        proxyLp.withdraw(asset_, amounts_, to_, toChainId_, chainIds_);

        // assert

    }

    function testWithdrawCrossChain() public {

    }

    function testBorrow() public {
        // arrange
        vm.selectFork(opMainnet);

        ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
        input[0].aTokenImpl = address(aTokenImpl);
        input[0].stableDebtTokenImpl = address(stabledebtTokenImpl);
        input[0].variableDebtTokenImpl = address(variabledebtTokenImpl);
        input[0].underlyingAssetDecimals = 18;
        input[0].interestRateStrategyAddress = address(strategy);
        input[0].underlyingAsset = address(Underlying);
        input[0].treasury = vm.addr(35);
        input[0].incentivesController = vm.addr(17);
        input[0].superchainAsset = address(superchainAsset);
        input[0].underlyingAssetName = "Mock rupee";
        input[0].aTokenName = "aToken-Underlying";
        input[0].aTokenSymbol = "aUnderlying";
        input[0].variableDebtTokenName = "vDebt";
        input[0].variableDebtTokenSymbol = "vDBT";
        input[0].stableDebtTokenName = "vStable";
        input[0].stableDebtTokenSymbol = "vSBT";
        input[0].params = "v";
        input[0].salt = "salt";
        vm.prank(admin);
        proxyConfigurator.batchInitReserve(input);

        vm.prank(alice);
        Underlying.approve(address(proxyLp),1000);

        address asset = address(Underlying);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        address onBehalfOf = alice;
        uint16 referralCode = 0;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;

        vm.prank(alice);
        proxyLp.deposit(asset, amounts, onBehalfOf, referralCode, chainIds);

        // act
        address asset_ = address(Underlying);
        uint256[] memory amounts_ = new uint256[](1);
        amounts_[0] = 800;
        uint256[] memory interestRateMode_ = new uint256[](1);
        interestRateMode_[0] = 1;
        uint16 referralCode_ = 0;
        address onBehalfOf_ = bob;
        uint256 sendToChainId_ = block.chainid;
        uint256[] memory chainIds_ = new uint256[](1);
        chainIds_[0] = block.chainid;

        vm.prank(bob);
        proxyLp.borrow(asset_, amounts_, interestRateMode_, referralCode_, onBehalfOf_, sendToChainId_, chainIds_);

        // assert
    }

    function testBorrowCrossChain() public {

    }

    function testRepay() public {
        // arrange

        // act
        address asset = address(Underlying);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 800;
        uint256 totalAmount = 800;
        uint256[] memory rateMode = new uint256[](1);
        rateMode[0] = 1;
        address onBehalfOf = bob;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;

        vm.prank(alice);
        proxyLp.repay(asset, amounts, totalAmount, rateMode, onBehalfOf, chainIds);

        // assert
    }

    function testRepayCrossChain() public {

    }
}