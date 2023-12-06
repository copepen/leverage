//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract VaultList {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _vaults; // list of vaults
    mapping(address => EnumerableSet.AddressSet) private _vaultsByOwner; // list of vaults owned by owner

    /**
     * @dev Returns length of vaults
     */
    function vaultLength() external view returns (uint256) {
        return _vaults.length();
    }

    /**
     * @dev Returns vault listed status
     * @param  _vault address of vault
     */
    function containsVault(address _vault) public view returns (bool) {
        return _vaults.contains(_vault);
    }

    /**
     * @dev Returns length of vaults owner has
     * @param  _owner address of owner
     */
    function vaultsByOwnerLength(address _owner) public view returns (uint256) {
        return _vaultsByOwner[_owner].length();
    }

    /**
     * @dev Returns vault address of owner by index
     * @param  _owner address of owner
     * @param  _index number of vault index
     */
    function vaultsByOwner(
        address _owner,
        uint256 _index
    ) external view returns (address) {
        return _vaultsByOwner[_owner].at(_index);
    }

    /**
     * @dev Add vault
     * @param  _owner address of vault owner
     * @param  _vault address of vault
     */
    function _addVault(address _owner, address _vault) internal {
        _vaults.add(_vault);
        _vaultsByOwner[_owner].add(_vault);
    }

    /**
     * @dev Remove vault
     * @param  _owner address of vault owner
     * @param  _vault address of vault
     */
    function _removeVault(address _owner, address _vault) internal {
        _vaults.remove(_vault);
        _vaultsByOwner[_owner].remove(_vault);
    }

    /**
     * @dev Transfer vault
     * @param  _from address of old vault owner
     * @param  _to address of new vault owner
     * @param  _vault address of vault
     */
    function _transferVault(
        address _from,
        address _to,
        address _vault
    ) internal {
        _vaultsByOwner[_from].remove(_vault);
        _vaultsByOwner[_to].add(_vault);
    }
}
