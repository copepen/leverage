//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVault {
    function totalCollateral() external view returns (uint256);

    function debtAmount() external view returns (uint256);

    function vaultOwner() external view returns (address);

    function collToken() external view returns (address);

    function debt() external view returns (uint256);

    function healthFactor(
        bool _useMlr
    ) external view returns (uint256 _healthFactor);

    function borrowableWithDiff(
        address _collateral,
        uint256 _diffAmount,
        bool _isAdd,
        bool _useMlr
    ) external view returns (uint256 _maxBorrowable, uint256 _borrowable);

    function setName(string memory _name) external;

    function transferVaultOwnership(address _newOwner) external;

    function addCollateral(uint256 _amount) external;

    function removeCollateral(uint256 _amount, address _to) external;

    function addBadDebt(uint256 _amount) external;

    function borrowable()
        external
        view
        returns (uint256 _maxBorrowable, uint256 _borrowable);

    function borrow(uint256 _amount) external;
}
