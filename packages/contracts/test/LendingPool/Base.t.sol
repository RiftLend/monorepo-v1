import {Test} from "../../lib/forge-std/src/Test.sol";
import {TestPlus} from "@solady-test/utils/TestPlus.sol";

import {ILendingPoolAddressesProvider} from "../../src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "../../src/interfaces/ILendingPoolConfigurator.sol";

import {TestERC20} from "../utils/TestERC20.sol";
import {SuperchainAsset} from "../../src/SuperchainAsset.sol";
import {AToken} from "../../src/tokenization/AToken.sol";
import {StableDebtToken} from "../../src/tokenization/StableDebtToken.sol";
import {VariableDebtToken} from "../../src/tokenization/VariableDebtToken.sol";
import {LendingPool} from "../../src/LendingPool.sol";
import {LendingPoolAddressesProvider} from "../../src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "../../src/LendingPoolConfigurator.sol";
import {DefaultReserveInterestRateStrategy} from "../../src/DefaultReserveInterestRateStrategy.sol";

contract BaseTest is Test, TestPlus {

    struct temps {
        address owner;
        address emergencyAdmin;
        address proxyAdmin;
        address poolAdmin;
        address lendingPoolConfigurator;
        address lendingPoolAddressesProvider;
        mapping (address underlyingAsset => Market) markets;
    }

    struct Market {
        uint256 marketId;
        address underlyingAsset;
        address aTokenImpl;
        address stableDebtTokenImpl;
        address variableDebtTokenImpl;
        address superchainAsset;
        address aToken;
        address variableDebtToken;
        address stableDebtToken;
        address interestRateStrategy;
        address treasury;
        address incentivesController;
    }

    address testToken;
    mapping (uint256 chainId => temps) public config;

    // chains
    uint256[2] internal chainId = [vm.envUint256("TEST_Chain_Id_1"), vm.envString("TEST_Chain_Id_2")];
    string[2] internal rpcs = [vm.envString("TEST_RPC_URL_1"), vm.envString("TEST_RPC_URL_2")];
    
    function setUp() public {
        address owner = _randomNonZeroAddress();
        for (uint256 i = 0; i < chainId.length; i++) {
            _configure(chainId[i], rpcs[i], owner);
        }
    }

    function _configure(uint256 _chainId, string memory _rpc, address _owner) internal {
        temps storage t = config[_chainId];
        vm.createSelectFork(rpc);

        t.owner = _owner;
        t.emergencyAdmin = _owner;
        t.proxyAdmin = _owner;

        // Deploy underlyingAsset
        TestERC20 underlyingAsset = new TestERC20("TUSDC", "USDC", 6);
        vm.label(address(underlyingAsset), "underlyingAsset");


        // Deploy SuperProxyAdmin
        address superProxyAdmin = address(new SuperProxyAdmin{salt: "superProxyAdmin"}());
        vm.label(superProxyAdmin, "superProxyAdmin");
        t.proxyAdmin = superProxyAdmin;

        // deploy implementations
        t.aTokenImpl = address( new AToken{salt: "aTokenImpl"}());
        t.stableDebtTokenImpl = address(new StableDebtToken{salt: "stableDebtTokenImpl"}());
        t.variableDebtTokenImpl = address(new VariableDebtToken{salt: "variableDebtTokenImpl"}());

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
