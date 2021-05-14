pragma solidity ^0.4.23;

import "./Roles.sol";

contract MinterRole {

    uint256 private _pause = 0;

    using Roles for Roles.Role;

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event Pause();
    event Unpause();

    Roles.Role private _minters;

    constructor () internal {
        _addMinter(msg.sender);
    }

    modifier onlyMinter() {
        require(isMinter(msg.sender));
        _;
    }

    function isMinter(address account) public view returns (bool) {
        return _minters.has(account);
    }

    function addMinter(address account) public onlyMinter {
        _addMinter(account);
    }

    function renounceMinter() public {
        _removeMinter(msg.sender);
    }

    function _addMinter(address account) internal {
        _minters.add(account);
        emit MinterAdded(account);
    }

    function _removeMinter(address account) internal {
        _minters.remove(account);
        emit MinterRemoved(account);
    }

    function pause() public onlyMinter {
        _pause = 1;
        emit Pause();
    }
    function unpause() public onlyMinter {
        _pause = 0;
        emit Unpause();
    }

    function getPause() external view returns (uint256) {
        return _pause;
    }
    modifier whenNotPaused() {
        require(_pause == 0);
        _;
    }
}
