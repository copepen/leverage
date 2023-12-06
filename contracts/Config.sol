//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IConfig.sol";

contract Config is IConfig {
    address public borrowFeeRecipient;
    mapping(address => CollateralInfo) public collateralInfo;

    /**
     * @dev Returns collateral info
     * @param  _token address of token
     */
    function getCollateralInfo(
        address _token
    ) external view override returns (CollateralInfo memory) {
        return collateralInfo[_token];
    }

    /**
     * @dev Returns collateral token listing status
     * @param  _token address of token
     */
    function isRegistered(
        address _token
    ) external view override returns (bool) {
        return collateralInfo[_token].isActive;
    }

    /**
     * @dev Returns collateral token price
     * @param  _token address of token
     */
    function tokenPrice(address _token) public view override returns (uint256) {
        (, int answer, , uint256 updatedAt, ) = AggregatorV3Interface(
            collateralInfo[_token].priceFeed
        ).latestRoundData();

        // TODO: should implement heartbeat check to prevent price manimulation
        uint256 heartbeatInterval = 7200;
        require(
            block.timestamp - updatedAt <= heartbeatInterval,
            "ORACLE_HEARTBEAT_FAILED"
        );

        return uint256(answer);
    }

    /**
     * @dev Set borrow fee recipient
     * @param  _borrowFeeRecipient address of borrow fee recipient
     */
    function setBorrowFeeRecipient(
        address _borrowFeeRecipient
    ) external override {
        _setBorrowFeeRecipient(_borrowFeeRecipient);
    }

    /**
     * @dev Add new collateral
     * @param  _token address of token
     * @param  _priceFeed address of priceFeed
     * @param  _mcr value of mcr
     * @param  _mlr value of mlr
     * @param  _issuanceFee issuance fee
     * @param  _decimals value of decimals
     * @param  _isActive status of collateral
     */
    function addCollateral(
        address _token,
        address _priceFeed,
        uint256 _mcr,
        uint256 _mlr,
        uint256 _issuanceFee,
        uint256 _decimals,
        bool _isActive
    ) external override {
        CollateralInfo memory collateral = collateralInfo[_token];

        collateral.token = _token;
        collateral.priceFeed = _priceFeed;
        collateral.mcr = _mcr;
        collateral.mlr = _mlr;
        collateral.issuanceFee = _issuanceFee;
        collateral.decimals = _decimals;
        collateral.isActive = _isActive;

        collateralInfo[_token] = collateral;

        emit NewCollateralAdded(
            _token,
            _priceFeed,
            _mcr,
            _mlr,
            _issuanceFee,
            _decimals,
            _isActive
        );
    }

    /**
     * @dev Set borrow fee recipient
     * @param  _borrowFeeRecipient address of borrow fee recipient
     */
    function _setBorrowFeeRecipient(address _borrowFeeRecipient) internal {
        require(_borrowFeeRecipient != address(0x0), "Zero address");
        borrowFeeRecipient = _borrowFeeRecipient;
    }
}
