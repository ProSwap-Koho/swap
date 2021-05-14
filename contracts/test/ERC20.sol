pragma solidity ^0.4.23;

import '../KswapERC20.sol';

contract ERC20 is KswapERC20 {
    constructor(uint _totalSupply) public {
        _mint(msg.sender, _totalSupply);
    }
}
