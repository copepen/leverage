//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IConfig {
    event NewCollateralAdded(
        address token,
        address priceFeed,
        uint256 mcr,
        uint256 mlr,
        uint256 borrowRate,
        uint256 decimals,
        bool isActive
    );

    struct CollateralInfo {
        address token; // collateral token address
        address priceFeed; // chainlink price feed address
        uint256 mcr; // minimum collateral ratio. For i.e, 110%, 250%
        uint256 mlr; // minimum liquiation ratio. For i.e, 105%, 110%
        uint256 issuanceFee; // issuance fee. For i.e, 1% -> 100, 2% -> 200
        uint256 decimals; // collateral token decimals. For i.e, 18
        bool isActive; // flag to represent if collateral is listed
    }

    function borrowFeeRecipient() external view returns (address);

    function tokenPrice(address _token) external view returns (uint256);

    function getCollateralInfo(
        address
    ) external view returns (CollateralInfo memory);

    function isRegistered(address) external view returns (bool);

    function addCollateral(
        address _token,
        address _priceFeed,
        uint256 _mcr,
        uint256 _mlr,
        uint256 _issuanceFee,
        uint256 _decimals,
        bool _isActive
    ) external;

    function setBorrowFeeRecipient(address _borrowFeeRecipient) external;
}
