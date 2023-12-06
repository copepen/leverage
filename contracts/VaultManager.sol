//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./Vault.sol";
import "./VaultList.sol";

import "./interfaces/IWETH.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IConfig.sol";

contract VaultManager is ReentrancyGuard, VaultList, Ownable {
    using SafeERC20 for IERC20;

    address public euro3Treasury; // address of treasury that mints EURO3 to users
    address public vaultLeverageZapper; // address of VaultLeverageZapper contract
    address public config; // address of Config contract
    address public debtToken; // address of debt token
    uint256 public totalDebt; // amount of EURO3
    mapping(address => uint256) public collateral; // mapping of collateral

    event VaultCreated(
        address indexed vault,
        string name,
        address indexed owner
    );
    event VaultOwnerChanged(
        address indexed vault,
        address indexed oldOwner,
        address indexed newOwner
    );

    modifier onlyVaultLeverageZapper() {
        require(msg.sender == vaultLeverageZapper, "Only leverage");
        _;
    }

    modifier onlyValidVault(address _vault) {
        require(containsVault(_vault), "Vault not listed");
        _;
    }

    modifier onlyValidCollateral(address _collateral) {
        require(
            IConfig(config).isRegistered((_collateral)),
            "Collateral not supported"
        );
        _;
    }

    modifier onlyVaultOwner(address _vault) {
        require(IVault(_vault).vaultOwner() == msg.sender, "Only vault owner");
        _;
    }

    constructor(
        address _debtToken,
        address _euro3Treasury
    ) Ownable(msg.sender) {
        require(_debtToken != address(0x0), "Zero address");
        require(_euro3Treasury != address(0x0), "Zero address");

        debtToken = _debtToken;
        euro3Treasury = _euro3Treasury;
    }

    /**
     * @dev Create a new vault
     * @param  _name string of vault name
     * @param  _creator address of vault creator/owner
     * @param  _collToken address of collateral token
     */
    function createVault(
        string memory _name,
        address _creator,
        address _collToken
    ) public onlyVaultLeverageZapper nonReentrant returns (address) {
        Vault vault = new Vault(_collToken, _creator, address(this), _name);
        address vaultAddr = address(vault);

        _addVault(_creator, vaultAddr);
        emit VaultCreated(vaultAddr, _name, _creator);
        return vaultAddr;
    }

    /**
     * @dev Add collateral
     * @param  _vault address of vault
     * @param  _collToken address of collateral token
     * @param  _amount amount of collateral token
     */
    function addCollateral(
        address _vault,
        address _collToken,
        uint256 _amount
    )
        public
        onlyVaultLeverageZapper
        onlyValidVault(_vault)
        onlyValidCollateral(_collToken)
        nonReentrant
    {
        collateral[_collToken] += _amount;

        IERC20(_collToken).safeTransferFrom(msg.sender, _vault, _amount);
        IVault(_vault).addCollateral(_amount);
    }

    /**
     * @dev Remove collateral
     * @param  _vault address of vault
     * @param  _collToken address of collateral token
     * @param  _amount amount of collateral token
     * @param  _to address of collateral token recipient
     */
    function removeCollateral(
        address _vault,
        address _collToken,
        uint256 _amount,
        address _to
    )
        public
        onlyVaultLeverageZapper
        onlyValidVault(_vault)
        onlyValidCollateral(_collToken)
        nonReentrant
    {
        IVault(_vault).removeCollateral(_amount, _to);
        collateral[_collToken] -= _amount;
    }

    /**
     * @dev Borrow debt
     * @param  _vault address of vault
     * @param  _amount amount of debt token
     */
    function borrow(
        address _vault,
        uint256 _amount
    )
        public
        onlyVaultLeverageZapper
        onlyValidVault(_vault)
        nonReentrant
        returns (uint256 borrowedAmount)
    {
        // 1. update total debt
        totalDebt += _amount;

        // 2. mint debt(EURO3)
        borrowedAmount = _mintDebt(_vault, _amount);

        // 3. borrow from vault
        IVault(_vault).borrow(borrowedAmount);
    }

    /**
     * @dev Transfer Vault ownership
     * @param  _vault address of vault
     * @param  _newOwner address of new owner of vault
     */
    function transferVaultOwnership(
        address _vault,
        address _newOwner
    ) public onlyVaultLeverageZapper onlyValidVault(_vault) nonReentrant {
        address currentOwner = msg.sender;
        require(_newOwner != address(0x0), "Zero address");

        emit VaultOwnerChanged(_vault, currentOwner, _newOwner);
        IVault(_vault).transferVaultOwnership(_newOwner);
        _transferVault(currentOwner, _newOwner, _vault);
    }

    /**
     * @dev Set Config
     * @param  _config address of config
     */
    function setConfig(address _config) external onlyOwner {
        config = _config;
    }

    /**
     * @dev Set VaultLeverageZapper
     * @param  _vaultLeverageZapper address of VaultLeverageZapper
     */
    function setVaultLeverageZapper(
        address _vaultLeverageZapper
    ) external onlyOwner {
        vaultLeverageZapper = _vaultLeverageZapper;
    }

    /**
     * @dev Mint EURO3
     * @param  _vault address of vault
     * @param  _amount amount of debt token
     */
    function _mintDebt(
        address _vault,
        uint256 _amount
    ) internal returns (uint256 _mintedDebt) {
        IConfig.CollateralInfo memory collateralInfo = IConfig(config)
            .getCollateralInfo(IVault(_vault).collToken());
        uint256 feeAmount = (_amount * collateralInfo.issuanceFee) /
            Constants.ISSUANCE_FEE_DECIMAL_PRECISON;

        _mintedDebt = _amount - feeAmount;

        IERC20(debtToken).safeTransferFrom(
            euro3Treasury,
            msg.sender,
            _amount - feeAmount
        );

        IERC20(debtToken).safeTransferFrom(
            euro3Treasury,
            IConfig(config).borrowFeeRecipient(),
            feeAmount
        );
    }

    receive() external payable {}
}
