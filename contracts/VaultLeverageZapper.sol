// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./utils/Constants.sol" as Constants;

import "./interfaces/IVault.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/ITokenSwapper.sol";
import "./interfaces/IWETH.sol";

contract VaultLeverageZapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IVaultManager public vaultManager; // address of VaultManager contract
    ITokenSwapper public tokenSwapper; // address of TokenSwapper contract
    string public prefix = "MyVault"; // string of prefix used fof vault name generation

    event LeverageZapperDeposited(
        address user,
        address collToken,
        uint256 collAmount,
        uint256 timestamp
    );

    constructor(address _vaultManager) Ownable(msg.sender) {
        setVaultManager(_vaultManager);
    }

    /**
     * @dev Set vault manager
     * @param  _vaultManager address of VaultManger contract
     */
    function setVaultManager(address _vaultManager) public onlyOwner {
        require(_vaultManager != address(0), "VaultManager: zero address");
        vaultManager = IVaultManager(_vaultManager);
    }

    /**
     * @dev Set token swapper
     * @param  _tokenSwapper address of TokenSwapper contract
     */
    function setTokenSwapper(address _tokenSwapper) public onlyOwner {
        require(_tokenSwapper != address(0), "TokenSwapper: zero address");
        tokenSwapper = ITokenSwapper(_tokenSwapper);
    }

    /**
     * @dev Set prefix
     * @param  _prefix string of prefix used for vault name generation
     */
    function setPrefix(string memory _prefix) public onlyOwner {
        prefix = _prefix;
    }

    /**
     * @dev Deposit ERC20 token with leverage
     * @param  _collToken address of collateral token
     * @param  _collAmount amount of collateral token
     */
    function deposit(
        address _collToken,
        uint256 _collAmount,
        bool _isLeveraged,
        ITokenSwapper.SwapPath[] memory path
    ) external nonReentrant {
        if (_collAmount > 0) {
            IERC20(_collToken).safeTransferFrom(
                msg.sender,
                address(this),
                _collAmount
            );
        }
        _deposit(_collToken, _collAmount, _isLeveraged, path);
    }

    /**
     * @dev Deposit ETH with leverage
     */
    function depositETH(
        bool _isLeveraged,
        ITokenSwapper.SwapPath[] memory path
    ) external payable nonReentrant {
        IWETH(Constants.WETH).deposit{value: msg.value}();

        _deposit(Constants.WETH, msg.value, _isLeveraged, path);
    }

    /**
     * @dev Deposit ERC20 token with leverage
     * @param  _collToken address of collateral token
     * @param  _collAmount amount of collateral token
     */
    function _deposit(
        address _collToken,
        uint256 _collAmount,
        bool _isLeveraged,
        ITokenSwapper.SwapPath[] memory path
    ) internal {
        require(_collAmount > 0, "Zero amount");

        // 1. Create vault
        address vault = vaultManager.createVault(
            _getNextVaultName(msg.sender),
            msg.sender,
            _collToken
        );

        // 2. Adds collaberal
        IERC20(_collToken).forceApprove(address(vaultManager), _collAmount);
        vaultManager.addCollateral(vault, _collToken, _collAmount);

        // 3. Borrow max amount of Euro3
        (uint256 maxBorrowable, ) = IVault(vault).borrowable();

        if (maxBorrowable > 0) {
            uint256 borrowedAmount = vaultManager.borrow(vault, maxBorrowable);

            if (_isLeveraged) {
                // 4. Swap EURO3 for collateral
                IERC20(Constants.EURO3).forceApprove(
                    address(tokenSwapper),
                    borrowedAmount
                );
                uint256 addtionalCollAmount = tokenSwapper.executeSwap(
                    borrowedAmount,
                    path,
                    0
                );

                // 5. Adds newly obtained collateral
                IERC20(_collToken).forceApprove(
                    address(vaultManager),
                    addtionalCollAmount
                );
                vaultManager.addCollateral(
                    vault,
                    _collToken,
                    addtionalCollAmount
                );
            } else {
                IERC20(Constants.EURO3).transfer(msg.sender, borrowedAmount);
            }
        }

        // 6. Transfer the ownership to the vault back to user
        vaultManager.transferVaultOwnership(vault, msg.sender);

        emit LeverageZapperDeposited(
            msg.sender,
            _collToken,
            _collAmount,
            block.timestamp
        );
    }

    /**
     * @dev Get name of next vault
     * @param  _owner address of vault owner
     */
    function _getNextVaultName(
        address _owner
    ) internal view returns (string memory) {
        uint256 vaultCount = vaultManager.vaultsByOwnerLength(_owner) + 1;
        return string.concat(prefix, Strings.toString(vaultCount));
    }

    receive() external payable {}
}
