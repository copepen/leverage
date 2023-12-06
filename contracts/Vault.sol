//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./utils/Constants.sol" as Constants;

import "./interfaces/IVaultManager.sol";
import "./interfaces/IConfig.sol";

contract Vault is Context {
    string public constant VERSION = "1.0.0";

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public vaultManager; // address of VaultManager contract
    address public vaultOwner; // address of vault owner
    address public collToken; // address of collateral token
    uint256 public totalCollateral; // amount of locked collateral token
    uint256 public debtAmount; // amount of borrowed debt token
    string public name; // string of vault name

    event CollateralAdded(
        address indexed collateral,
        uint256 amount,
        uint256 user
    );
    event CollateralRemoved(
        address indexed collateral,
        uint256 amount,
        uint256 newTotalAmount
    );
    event DebtAdded(uint256 amount, uint256 newTotalDebt);

    modifier onlyVaultOwner() {
        require(msg.sender == vaultOwner, "Only vault owner");
        _;
    }

    modifier onlyVaultManager() {
        require(msg.sender == vaultManager, "Only vault manager");
        _;
    }

    constructor(
        address _collToken,
        address _vaultOwner,
        address _vaultManager,
        string memory _name
    ) {
        require(_collToken != address(0x0), "Zero Colleteral");
        require(_vaultOwner != address(0x0), "Zero Address");
        require(_vaultManager != address(0x0), "Zero address");
        require(bytes(_name).length > 0, "Empty Name");

        collToken = _collToken;
        vaultManager = _vaultManager;
        vaultOwner = _vaultOwner;
        name = _name;
    }

    /**
     * @dev Get borrowable amount
     */
    function borrowable()
        public
        view
        returns (uint256 _maxBorrowable, uint256 _borrowable)
    {
        (_maxBorrowable, _borrowable) = borrowableWithDiff(
            collToken,
            0,
            false,
            false
        );
    }

    /**
     * @dev Get health factor
     * @param  _useMlr flag to use MLR for HF calculation or not
     */
    function healthFactor(bool _useMlr) public view returns (uint256) {
        if (debtAmount == 0) return type(uint256).max;

        (uint256 maxBorrowable, ) = borrowableWithDiff(
            collToken,
            0,
            false,
            _useMlr
        );

        return (maxBorrowable * 1e4) / debtAmount;
    }

    /**
     * @dev Get borrowable amount
     * @param  _collToken address of collateral token
     * @param  _collAmount amount of collateral token
     * @param  _isAdd flag to show add/remove
     * @param  _useMlr flag to use MLR for HF calculation or not
     */
    function borrowableWithDiff(
        address _collToken,
        uint256 _collAmount,
        bool _isAdd,
        bool _useMlr
    ) public view returns (uint256, uint256) {
        address config = IVaultManager(vaultManager).config();
        require(
            IConfig(config).isRegistered((_collToken)),
            "Collateral not supported"
        );
        uint256 newCollAmount = totalCollateral;
        if (_isAdd) {
            newCollAmount = totalCollateral + _collAmount;
        } else {
            newCollAmount = totalCollateral - _collAmount;
        }

        IConfig.CollateralInfo memory collateralInfo = IConfig(config)
            .getCollateralInfo(collToken);

        uint256 collTokenPrice = IConfig(config).tokenPrice(_collToken);
        uint256 normalizedCollAmount = newCollAmount *
            (10 ** (18 - collateralInfo.decimals));
        uint256 collBorrowable = (normalizedCollAmount * collTokenPrice) /
            Constants.PRICE_DECIMAL_PRECISON;
        uint256 borrowableAmount = (collBorrowable * 100) /
            (_useMlr ? collateralInfo.mlr : collateralInfo.mcr);

        return (
            borrowableAmount,
            (borrowableAmount > debtAmount) ? borrowableAmount - debtAmount : 0
        );
    }

    /**
     * @dev Set vault name
     * @param  _name string of vault name
     */
    function setName(string memory _name) external onlyVaultOwner {
        require(bytes(_name).length > 0, "Empty Name");
        name = _name;
    }

    /**
     * @dev Transfer vault ownership
     * @param  _newOwner address of new vault owner
     */
    function transferVaultOwnership(
        address _newOwner
    ) external onlyVaultManager {
        vaultOwner = _newOwner;
    }

    /**
     * @dev Add collateral
     * @param  _amount amount of collateral token
     */
    function addCollateral(uint256 _amount) external onlyVaultManager {
        require(_amount > 0, "Zero Amount");

        totalCollateral += _amount;

        emit CollateralAdded(collToken, _amount, totalCollateral);
    }

    /**
     * @dev Remove collateral
     * @param  _amount amount of collateral token
     * @param  _to address of collateral token recipient
     */
    function removeCollateral(
        uint256 _amount,
        address _to
    ) external onlyVaultManager {
        require(_amount > 0, "Zero Amount");
        require(healthFactor(false) >= 1e4, "Low HF");

        totalCollateral -= _amount;
        IERC20(collToken).safeTransfer(_to, _amount);

        emit CollateralRemoved(collToken, _amount, totalCollateral);
    }

    /**
     * @dev Borrow debt
     * @param  _amount amount of debt token
     */
    function borrow(uint256 _amount) external onlyVaultManager {
        require(_amount > 0, "Zero Amount");

        (uint256 _maxBorrowable, uint256 _borrowable) = borrowable();
        require(_amount <= _borrowable, "Not Enough Borrowable");

        debtAmount += _amount;
        require(debtAmount <= _maxBorrowable, "Max Borrowable");

        emit DebtAdded(_amount, debtAmount);
    }

    /**
     * @dev Repay debt
     * @param  _amount amount of debt token
     */
    function repay(uint256 _amount) external onlyVaultManager {
        // TODO: should implement redeem logic
    }

    /**
     * @dev Redeem
     * @param  _amount amount of debt token
     */
    function redeem(uint256 _amount) external onlyVaultManager {
        // TODO: should implement redeem logic
    }

    /**
     * @dev Liquidate
     */
    function liquidate() external {
        // TODO: should implement liquidation logic
    }
}
