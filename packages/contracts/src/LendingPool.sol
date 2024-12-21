// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";

import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "./interfaces/IAToken.sol";
import {IVariableDebtToken} from "./interfaces/IVariableDebtToken.sol";
import {IFlashLoanReceiver} from "./interfaces/IFlashLoanReceiver.sol";
import {IPriceOracleGetter} from "./interfaces/IPriceOracleGetter.sol";
import {IStableDebtToken} from "./interfaces/IStableDebtToken.sol";
import "./interfaces/ILendingPool.sol";
import {ISuperchainAsset} from "./interfaces/ISuperchainAsset.sol";

import {Initializable} from "@solady/utils/Initializable.sol";
import {Helpers} from "./libraries/helpers/Helpers.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {WadRayMath} from "./libraries/math/WadRayMath.sol";
import {PercentageMath} from "./libraries/math/PercentageMath.sol";
import {ReserveLogic} from "./libraries/logic/ReserveLogic.sol";
import {GenericLogic} from "./libraries/logic/GenericLogic.sol";
import {ValidationLogic} from "./libraries/logic/ValidationLogic.sol";
import {ReserveConfiguration} from "./libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "./libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {LendingPoolStorage} from "./LendingPoolStorage.sol";
import {Predeploys} from "@contracts-bedrock/libraries/Predeploys.sol";
import {SuperPausable} from "@interop-std/utils/SuperPausable.sol";

/**
 * @title LendingPool contract
 * @dev Main point of interaction with an Aave protocol's market
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Borrow
 *   # Repay
 *   # Swap their loans between variable and stable rate
 *   # Enable/disable their deposits as collateral rebalance stable rate borrow positions
 *   # Liquidate positions
 *   # Execute Flash Loans
 * - To be covered by a proxy contract, owned by the LendingPoolAddressesProvider of the specific market
 * - All admin functions are callable by the LendingPoolConfigurator contract defined also in the
 *   LendingPoolAddressesProvider
 * @author tabish.eth (superlend@proton.me)
 *
 */
contract LendingPool is Initializable, LendingPoolStorage, SuperPausable {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;

    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    bytes2 private constant UPDATE_STATE_MASK = bytes2(uint16(1));
    bytes2 private constant UPDATE_RATES_MASK = bytes2(uint16(2));
    uint256 public constant LENDINGPOOL_REVISION = 0x2;

    modifier onlyLendingPoolConfigurator() {
        _onlyLendingPoolConfigurator();
        _;
    }

    function _onlyLendingPoolConfigurator() internal view {
        require(
            _addressesProvider.getLendingPoolConfigurator() == msg.sender,
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
    }

    modifier onlyRouter() {
        _onlyRouter();
        _;
    }

    function _onlyRouter() internal view {
        require(_addressesProvider.getRouter() == msg.sender, "!router");
    }

    modifier onlyRouterOrSelf() {
        _onlyRouterOrSelf();
        _;
    }

    function _onlyRouterOrSelf() internal view {
        require(_addressesProvider.getRouter() == msg.sender || msg.sender == address(this), "!router || !self");
    }

    /**
     * @dev Function is invoked by the proxy contract when the LendingPool contract is added to the
     * LendingPoolAddressesProvider of the market.
     * - Caching the address of the LendingPoolAddressesProvider in order to reduce gas consumption
     *   on subsequent operations
     * @param provider The address of the LendingPoolAddressesProvider
     *
     */
    function initialize(ILendingPoolAddressesProvider provider) public initializer {
        _addressesProvider = provider;
        _maxStableRateBorrowSizePercent = 2500;
        _flashLoanPremiumTotal = 9;
        _maxNumberOfReserves = 128;
    }

    function deposit(address sender, address asset /* underlying */, uint256 amount, address onBehalfOf, uint16 referralCode)
        external
        onlyRouter
    {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        address aToken = reserve.aTokenAddress;
        address superchainAsset = reserve.superchainAssetAddress;

        ValidationLogic.validateDeposit(reserve, amount);

        _updateStates(reserve, asset, amount, 0, bytes2(uint16(3)));

        // get the rVaultToken address
        IERC20(asset).safeTransferFrom(sender, address(this), amount);
        IERC20(asset).safeIncreaseAllowance(superAsset, amount);
        ISuperchainAsset(superchainAsset).mint(aToken, amount);

        (bool isFirstDeposit, uint256 mintMode, uint256 amountScaled) =
            IAToken(aToken).mint(onBehalfOf, amount, reserve.liquidityIndex);

        if (isFirstDeposit) {
            _usersConfig[onBehalfOf].setUsingAsCollateral(reserve.id, true);
            emit ReserveUsedAsCollateralEnabled(asset, onBehalfOf);
        }

        emit Deposit(sender, asset, amount, onBehalfOf, referralCode, mintMode, amountScaled);
    }

    function updateStates(address asset, uint256 depositAmount, uint256 withdrawAmount, bytes2 mask)
        public
        onlyRouterOrSelf
    {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        _updateStates(reserve, asset, depositAmount, withdrawAmount, mask);
    }

    function _updateStates(
        DataTypes.ReserveData storage reserve,
        address asset,
        uint256 depositAmount,
        uint256 withdrawAmount,
        bytes2 mask
    ) internal {
        if (mask & UPDATE_STATE_MASK != 0) reserve.updateState();
        if (mask & UPDATE_RATES_MASK != 0) {
            reserve.updateInterestRates(asset, reserve.aTokenAddress, depositAmount, withdrawAmount);
        }
    }

    function withdraw(address sender, address asset, uint256 amount, address to, uint256 toChainId)
        external
        onlyRouter
    {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        address aToken = reserve.aTokenAddress;

        uint256 userBalance = IAToken(aToken).balanceOf(sender);
        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;

        ValidationLogic.validateWithdraw(
            asset,
            amountToWithdraw,
            userBalance,
            _reserves,
            _usersConfig[sender],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        _updateStates(reserve, asset, 0, amountToWithdraw, bytes2(uint16(3)));

        if (amountToWithdraw == userBalance) {
            _usersConfig[sender].setUsingAsCollateral(reserve.id, false);
            emit ReserveUsedAsCollateralDisabled(asset, sender);
        }

        (uint256 mode, uint256 amountScaled) =
            IAToken(aToken).burn(sender, to, toChainId, amountToWithdraw, reserve.liquidityIndex);

        emit Withdraw(sender, asset, to, amountToWithdraw, mode, amountScaled);
    }

    function borrow(
        address sender,
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf,
        uint256 sendToChainId,
        uint16 referralCode
    ) external onlyRouter {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        _executeBorrow(
            ExecuteBorrowParams(
                asset,
                sender,
                onBehalfOf,
                sendToChainId,
                amount,
                interestRateMode,
                reserve.aTokenAddress,
                referralCode,
                true
            )
        );
    }

    // TODO: modify for #33
    function repay(address sender, address asset, uint256 amount, uint256 rateMode, address onBehalfOf)
        external
        onlyRouter
    {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        address superchainAsset = reserve.superchainAssetAddress;

        /// @dev this will get the debt of the user on the current chain
        (uint256 stableDebt, uint256 variableDebt) = Helpers.getUserCurrentDebt(onBehalfOf, reserve);

        DataTypes.InterestRateMode interestRateMode = DataTypes.InterestRateMode(rateMode);

        ValidationLogic.validateRepay(reserve, amount, interestRateMode, onBehalfOf, stableDebt, variableDebt);

        uint256 paybackAmount = interestRateMode == DataTypes.InterestRateMode.STABLE ? stableDebt : variableDebt;

        if (amount < paybackAmount) {
            paybackAmount = amount;
        }

        _updateStates(reserve, asset, paybackAmount, 0, bytes2(uint16(3)));

        uint256 mode;
        uint256 amountBurned;
        if (interestRateMode == DataTypes.InterestRateMode.STABLE) {
            (mode, amountBurned) = IStableDebtToken(reserve.stableDebtTokenAddress).burn(onBehalfOf, paybackAmount);
        } else {
            (mode, amountBurned) = IVariableDebtToken(reserve.variableDebtTokenAddress).burn(
                onBehalfOf, paybackAmount, reserve.variableBorrowIndex
            );
        }

        address aToken = reserve.aTokenAddress;

        if (stableDebt + variableDebt - paybackAmount == 0) {
            _usersConfig[onBehalfOf].setBorrowing(reserve.id, false);
        }

        IERC20(superchainAsset).safeTransfer(aToken, paybackAmount);

        if (amount - paybackAmount > 0) {
            IERC20(superchainAsset).safeTransfer(sender, amount - paybackAmount);
        }

        IAToken(aToken).handleRepayment(sender, paybackAmount);

        emit Repay(asset, paybackAmount, onBehalfOf, sender, rateMode, mode, amountBurned);
    }

    /**
     * @dev Allows a borrower to swap his debt between stable and variable mode, or viceversa
     * @param sender The address of the user swapping the debt
     * @param asset The address of the underlying asset borrowed
     * @param rateMode The rate mode that the user wants to swap to
     *
     */
    function swapBorrowRateMode(address sender, address asset, uint256 rateMode) internal {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        (uint256 stableDebt, uint256 variableDebt) = Helpers.getUserCurrentDebt(sender, reserve);

        DataTypes.InterestRateMode interestRateMode = DataTypes.InterestRateMode(rateMode);

        ValidationLogic.validateSwapRateMode(reserve, _usersConfig[sender], stableDebt, variableDebt, interestRateMode);

        reserve.updateState();

        uint256 variableDebtAmount;
        uint256 stableDebtAmount;
        if (interestRateMode != DataTypes.InterestRateMode.STABLE) {
            (, stableDebtAmount) = IStableDebtToken(reserve.stableDebtTokenAddress).burn(sender, stableDebt);
            (,, variableDebtAmount) = IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
                sender, sender, stableDebt, reserve.variableBorrowIndex
            );
        } else {
            (, variableDebtAmount) = IVariableDebtToken(reserve.variableDebtTokenAddress).burn(
                sender, variableDebt, reserve.variableBorrowIndex
            );
            (,, stableDebtAmount) = IStableDebtToken(reserve.stableDebtTokenAddress).mint(
                sender, sender, variableDebt, reserve.currentStableBorrowRate
            );
        }

        reserve.updateInterestRates(asset, reserve.aTokenAddress, 0, 0);

        emit Swap(asset, sender, rateMode, variableDebtAmount, stableDebtAmount);
    }

    /**
     * @dev Rebalances the stable interest rate of a user to the current stable rate defined on the reserve.
     * - Users can be rebalanced if the following conditions are satisfied:
     *     1. Usage ratio is above 95%
     *     2. the current deposit APY is below REBALANCE_UP_THRESHOLD * maxVariableBorrowRate, which means that too much has been
     *        borrowed at a stable rate and depositors are not earning enough
     * @param asset The address of the underlying asset borrowed
     * @param user The address of the user to be rebalanced
     *
     */
    function rebalanceStableBorrowRate(address asset, address user) external onlyRouter {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        IERC20 stableDebtToken = IERC20(reserve.stableDebtTokenAddress);
        IERC20 variableDebtToken = IERC20(reserve.variableDebtTokenAddress);
        address aTokenAddress = reserve.aTokenAddress;

        uint256 stableDebt = IERC20(stableDebtToken).balanceOf(user);

        ValidationLogic.validateRebalanceStableBorrowRate(
            reserve, asset, stableDebtToken, variableDebtToken, aTokenAddress
        );

        _updateStates(reserve, asset, 0, 0, bytes2(uint16(1)));

        (, uint256 amountBurned) = IStableDebtToken(address(stableDebtToken)).burn(user, stableDebt);
        (,, uint256 amountMinted) =
            IStableDebtToken(address(stableDebtToken)).mint(user, user, stableDebt, reserve.currentStableBorrowRate);

        _updateStates(reserve, asset, 0, 0, bytes2(uint16(2)));

        emit RebalanceStableBorrowRate(asset, user, amountBurned, amountMinted);
    }

    function setUserUseReserveAsCollateral(address sender, address asset, bool useAsCollateral) external onlyRouter {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        ValidationLogic.validateSetUseReserveAsCollateral(
            reserve,
            asset,
            useAsCollateral,
            _reserves,
            _usersConfig[sender],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        _usersConfig[sender].setUsingAsCollateral(reserve.id, useAsCollateral);

        emit ReserveUsedAsCollateral(sender, asset, useAsCollateral);
    }

    // TODO: modify for #33
    function liquidationCall(
        address sender,
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken,
        uint256 sendToChainId
    ) external onlyRouter {
        address collateralManager = _addressesProvider.getLendingPoolCollateralManager();

        // TODO: ERROR
        IERC20(debtAsset).safeTransferFrom(sender, collateralManager, debtToCover);

        //solium-disable-next-line
        (bool success, bytes memory result) = collateralManager.delegatecall(
            abi.encodeWithSignature(
                "liquidationCall(address,address,address,address,uint256,bool,uint256)",
                sender,
                collateralAsset,
                debtAsset,
                user,
                debtToCover,
                receiveAToken,
                sendToChainId
            )
        );

        require(success, Errors.LP_LIQUIDATION_CALL_FAILED);

        (uint256 returnCode, string memory returnMessage) = abi.decode(result, (uint256, string));

        require(returnCode == 0, string(abi.encodePacked(returnMessage)));
    }

    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        address oracle;
        uint256 i;
        address currentAsset;
        address currentATokenAddress;
        uint256 currentAmount;
        uint256 currentPremium;
        uint256 currentAmountPlusPremium;
        address debtToken;
    }

    /**
     * @dev Allows smartcontracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.
     * For further details please visit https://developers.aave.com
     * @param sender The address of the sender
     * @param receiverAddress The address of the contract receiving the funds, implementing the IFlashLoanReceiver interface
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts amounts being flash-borrowed
     * @param modes Types of the debt to open if the flash loan is not returned:
     *   0 -> Don't open any debt, just revert if funds can't be transferred from the receiver
     *   1 -> Open debt at stable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     *   2 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     * @param onBehalfOf The address  that will receive the debt in the case of using on `modes` 1 or 2
     * @param params Variadic packed params to pass to the receiver as extra information
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     *
     */
    function flashLoan(
        address sender,
        address receiverAddress,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory modes,
        address onBehalfOf,
        bytes memory params,
        uint16 referralCode
    ) external onlyRouter {
        FlashLoanLocalVars memory vars;

        ValidationLogic.validateFlashloan(assets, amounts);

        address[] memory aTokenAddresses = new address[](assets.length);
        uint256[] memory premiums = new uint256[](assets.length);

        vars.receiver = IFlashLoanReceiver(receiverAddress);

        for (vars.i = 0; vars.i < assets.length; vars.i++) {
            aTokenAddresses[vars.i] = _reserves[assets[vars.i]].aTokenAddress;

            premiums[vars.i] = amounts[vars.i] * _flashLoanPremiumTotal / 10000;

            IAToken(aTokenAddresses[vars.i]).transferUnderlyingTo(receiverAddress, amounts[vars.i], block.chainid);
        }

        require(
            vars.receiver.executeOperation(assets, amounts, premiums, sender, params),
            Errors.LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN
        );

        bool borrowExecuted = false;
        for (vars.i = 0; vars.i < assets.length; vars.i++) {
            vars.currentAsset = assets[vars.i];
            vars.currentAmount = amounts[vars.i];
            vars.currentPremium = premiums[vars.i];
            vars.currentATokenAddress = aTokenAddresses[vars.i];
            vars.currentAmountPlusPremium = vars.currentAmount + vars.currentPremium;

            if (DataTypes.InterestRateMode(modes[vars.i]) == DataTypes.InterestRateMode.NONE) {
                _reserves[vars.currentAsset].updateState();
                _reserves[vars.currentAsset].cumulateToLiquidityIndex(
                    IERC20(vars.currentATokenAddress).totalSupply(), vars.currentPremium
                );
                _reserves[vars.currentAsset].updateInterestRates(
                    vars.currentAsset, vars.currentATokenAddress, vars.currentAmountPlusPremium, 0
                );

                IERC20(vars.currentAsset).safeTransferFrom(
                    receiverAddress, address(this), vars.currentAmountPlusPremium
                );
                ISuperchainAsset(vars.currentAsset).mint(vars.currentATokenAddress, vars.currentAmountPlusPremium);
            } else {
                // If the user chose to not return the funds, the system checks if there is enough collateral and
                // eventually opens a debt position
                _executeBorrow(
                    ExecuteBorrowParams(
                        vars.currentAsset,
                        sender,
                        onBehalfOf,
                        block.chainid,
                        vars.currentAmount,
                        modes[vars.i],
                        vars.currentATokenAddress,
                        referralCode,
                        false
                    )
                );
                borrowExecuted = true;
            }
            emit FlashLoan(
                block.chainid,
                borrowExecuted,
                sender,
                vars.currentAsset,
                vars.currentAmount,
                vars.currentPremium,
                receiverAddress,
                referralCode
            );
        }
    }

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     *
     */
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        return _reserves[asset];
    }

    /**
     * @dev Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     *
     */
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        (totalCollateralETH, totalDebtETH, ltv, currentLiquidationThreshold, healthFactor) = GenericLogic
            .calculateUserAccountData(
            user, _reserves, _usersConfig[user], _reservesList, _reservesCount, _addressesProvider.getPriceOracle()
        );

        availableBorrowsETH = GenericLogic.calculateAvailableBorrowsETH(totalCollateralETH, totalDebtETH, ltv);
    }

    /**
     * @dev Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     *
     */
    function getConfiguration(address asset) external view returns (DataTypes.ReserveConfigurationMap memory) {
        return _reserves[asset].configuration;
    }

    /**
     * @dev Returns the configuration of the user across all the reserves
     * @param user The user address
     * @return The configuration of the user
     *
     */
    function getUserConfiguration(address user) external view returns (DataTypes.UserConfigurationMap memory) {
        return _usersConfig[user];
    }

    /**
     * @dev Returns the normalized income per unit of asset
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve's normalized income
     */
    function getReserveNormalizedIncome(address asset) external view virtual returns (uint256) {
        return _reserves[_reserves[asset].superchainAssetAddress].getNormalizedIncome();
    }

    /**
     * @dev Returns the normalized variable debt per unit of asset
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve normalized variable debt
     */
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256) {
        return _reserves[_reserves[asset].superchainAssetAddress].getNormalizedDebt();
    }

    /**
     * @dev Returns the list of the initialized reserves
     *
     */
    function getReservesList() external view returns (address[] memory) {
        address[] memory _activeReserves = new address[](_reservesCount);

        for (uint256 i = 0; i < _reservesCount; i++) {
            _activeReserves[i] = _reservesList[i];
        }
        return _activeReserves;
    }

    /**
     * @dev Returns the cached LendingPoolAddressesProvider connected to this contract
     *
     */
    function getAddressesProvider() external view returns (ILendingPoolAddressesProvider) {
        return _addressesProvider;
    }

    /**
     * @dev Returns the percentage of available liquidity that can be borrowed at once at stable rate
     */
    function MAX_STABLE_RATE_BORROW_SIZE_PERCENT() public view returns (uint256) {
        return _maxStableRateBorrowSizePercent;
    }

    /**
     * @dev Returns the fee on flash loans
     */
    function FLASHLOAN_PREMIUM_TOTAL() public view returns (uint256) {
        return _flashLoanPremiumTotal;
    }

    /**
     * @dev Returns the maximum number of reserves supported to be listed in this LendingPool
     */
    function MAX_NUMBER_RESERVES() public view returns (uint256) {
        return _maxNumberOfReserves;
    }

    /**
     * @dev Validates and finalizes an aToken transfer
     * - Only callable by the overlying aToken of the `asset`
     * @param asset The address of the underlying asset of the aToken
     * @param from The user from which the aTokens are transferred
     * @param to The user receiving the aTokens
     * @param amount The amount being transferred/withdrawn
     * @param balanceFromBefore The aToken balance of the `from` user before the transfer
     * @param balanceToBefore The aToken balance of the `to` user before the transfer
     */
    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external whenNotPaused {
        require(msg.sender == _reserves[asset].aTokenAddress, Errors.LP_CALLER_MUST_BE_AN_ATOKEN);

        ValidationLogic.validateTransfer(
            from, _reserves, _usersConfig[from], _reservesList, _reservesCount, _addressesProvider.getPriceOracle()
        );

        uint256 reserveId = _reserves[asset].id;

        if (from != to) {
            if (balanceFromBefore - amount == 0) {
                DataTypes.UserConfigurationMap storage fromConfig = _usersConfig[from];
                fromConfig.setUsingAsCollateral(reserveId, false);
                emit ReserveUsedAsCollateralDisabled(asset, from);
            }

            if (balanceToBefore == 0 && amount != 0) {
                DataTypes.UserConfigurationMap storage toConfig = _usersConfig[to];
                toConfig.setUsingAsCollateral(reserveId, true);
                emit ReserveUsedAsCollateralEnabled(asset, to);
            }
        }
    }

    /**
     * @dev Initializes a reserve, activating it, assigning an aToken and debt tokens and an
     * interest rate strategy
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param aTokenAddress The address of the aToken that will be assigned to the reserve
     * @param superchainAsset The address of the SuperchainAsset that will be assigned to the reserve
     * @param stableDebtAddress The address of the StableDebtToken that will be assigned to the reserve
     * @param aTokenAddress The address of the VariableDebtToken that will be assigned to the reserve
     * @param interestRateStrategyAddress The address of the interest rate strategy contract
     *
     */
    function initReserve(
        address asset,
        address superchainAsset,
        address aTokenAddress,
        address stableDebtAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external onlyLendingPoolConfigurator {
        require(asset.code.length > 0, Errors.LP_NOT_CONTRACT);
        _reserves[asset].init(
            aTokenAddress, superchainAsset, stableDebtAddress, variableDebtAddress, interestRateStrategyAddress
        );
        _addReserveToList(asset);
    }

    /**
     * @dev Updates the address of the interest rate strategy contract
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param rateStrategyAddress The address of the interest rate strategy contract
     *
     */
    function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress)
        external
        onlyLendingPoolConfigurator
    {
        _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
    }

    /**
     * @dev Sets the configuration bitmap of the reserve as a whole
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param configuration The new configuration bitmap
     *
     */
    function setConfiguration(address asset, uint256 configuration) external onlyLendingPoolConfigurator {
        _reserves[asset].configuration.data = configuration;
    }

    /**
     * @dev Sets the configuration bitmap of the reserve via cross-chain message
     * - Only callable by the LendingPoolConfigurator contract
     * @param _identifier Cross-chain message identifier containing origin and chain details
     * @param _data Encoded message data containing:
     *        - selector: Function selector to verify the cross-chain call
     *        - chainId: Target chain ID for the update
     *        - asset: The address of the underlying asset of the reserve
     *        - configuration: The new configuration bitmap
     * @notice Validates the cross-chain message origin and updates the reserve configuration
     * @notice Will revert if:
     *         - Message origin is not the LendingPoolConfigurator
     *         - Chain ID in message doesn't match current chain
     *         - Selector doesn't match ReserveConfigurationChanged
     */
    function setConfiguration(Identifier calldata _identifier, bytes calldata _data) external {
        if (_identifier.origin != _addressesProvider.getLendingPoolConfigurator()) {
            revert OriginNotLendingPoolConfigurator();
        }
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_identifier, keccak256(_data));

        (bytes32 selector, uint256 chainId, address asset, uint256 configuration) =
            abi.decode(_data, (bytes32, uint256, address, uint256));
        if (chainId != block.chainid) revert InvalidChainId(chainId);
        if (selector != ReserveConfigurationChanged.selector) revert InvalidSelector(selector);

        _reserves[asset].configuration.data = configuration;
    }

    struct ExecuteBorrowParams {
        address asset;
        address user;
        address onBehalfOf;
        uint256 sendToChainId;
        uint256 amount;
        uint256 interestRateMode;
        address aTokenAddress;
        uint16 referralCode;
        bool releaseUnderlying;
    }

    function _executeBorrow(ExecuteBorrowParams memory vars) internal {
        DataTypes.ReserveData storage reserve = _reserves[vars.asset];
        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[vars.onBehalfOf];

        address oracle = _addressesProvider.getPriceOracle();

        uint256 amountInETH = IPriceOracleGetter(oracle).getAssetPrice(vars.asset) * vars.amount
            / 10 ** reserve.configuration.getDecimals();

        ValidationLogic.validateBorrow(
            vars.asset,
            reserve,
            vars.onBehalfOf,
            vars.amount,
            amountInETH,
            vars.interestRateMode,
            _maxStableRateBorrowSizePercent,
            _reserves,
            userConfig,
            _reservesList,
            _reservesCount,
            oracle
        );

        _updateStates(reserve, address(0), 0, 0, bytes2(uint16(1)));

        uint256 currentStableRate = 0;
        uint256 mintMode = 0;
        uint256 amountScaled = 0;

        bool isFirstBorrowing = false;
        if (DataTypes.InterestRateMode(vars.interestRateMode) == DataTypes.InterestRateMode.STABLE) {
            currentStableRate = reserve.currentStableBorrowRate;

            (isFirstBorrowing, mintMode, amountScaled) = IStableDebtToken(reserve.stableDebtTokenAddress).mint(
                vars.user, vars.onBehalfOf, vars.amount, currentStableRate
            );
        } else {
            (isFirstBorrowing, mintMode, amountScaled) = IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
                vars.user, vars.onBehalfOf, vars.amount, reserve.variableBorrowIndex
            );
        }

        if (isFirstBorrowing) {
            userConfig.setBorrowing(reserve.id, true);
        }

        _updateStates(reserve, vars.aTokenAddress, 0, vars.releaseUnderlying ? vars.amount : 0, bytes2(uint16(2)));

        if (vars.releaseUnderlying) {
            IAToken(vars.aTokenAddress).transferUnderlyingTo(vars.user, vars.amount, vars.sendToChainId);
        }

        emit Borrow(
            vars.asset,
            vars.amount,
            vars.user,
            vars.onBehalfOf,
            vars.sendToChainId,
            vars.interestRateMode,
            DataTypes.InterestRateMode(vars.interestRateMode) == DataTypes.InterestRateMode.STABLE
                ? currentStableRate
                : reserve.currentVariableBorrowRate,
            mintMode,
            amountScaled,
            vars.referralCode
        );
    }

    function _addReserveToList(address asset) internal {
        uint256 reservesCount = _reservesCount;

        require(reservesCount < _maxNumberOfReserves, Errors.LP_NO_MORE_RESERVES_ALLOWED);

        bool reserveAlreadyAdded = _reserves[asset].id != 0 || _reservesList[0] == asset;

        if (!reserveAlreadyAdded) {
            _reserves[asset].id = uint8(reservesCount);
            _reservesList[reservesCount] = asset;

            _reservesCount = reservesCount + 1;
        }
    }

    /**
     * @dev Set the _pause state of a reserve
     * - Only callable by the LendingPoolConfigurator contract
     * @param val `true` to pause the reserve, `false` to un-pause it
     */
    function setPause(bool val) external onlyLendingPoolConfigurator {
        if (val) {
            _pause();
        } else {
            _unpause();
        }
    }
}
