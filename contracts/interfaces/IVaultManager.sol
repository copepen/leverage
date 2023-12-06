//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVaultManager {
    function config() external view returns (address);

    function containsVault(address _vault) external view returns (bool);

    function vaultsByOwnerLength(
        address _owner
    ) external view returns (uint256);

    function createVault(
        string memory _name,
        address _creator,
        address _collToken
    ) external returns (address);

    function removeCollateralNative(
        address _vault,
        uint256 _amount,
        address _to
    ) external;

    function addCollateral(
        address _vault,
        address _collateral,
        uint256 _amount
    ) external;

    function removeCollateral(
        address _vault,
        address _collateral,
        uint256 _amount,
        address _to
    ) external;

    function borrow(
        address _vault,
        uint256 _amount
    ) external returns (uint256 borrowedAmount);

    function transferVaultOwnership(address _vault, address _newOwner) external;
}
