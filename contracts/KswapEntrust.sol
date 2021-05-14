pragma solidity ^0.4.23;

import './libraries/SafeMath.sol';
import './libraries/MinterRole.sol';
import './interfaces/IERC20.sol';

interface ISwapPair {
    function invest(uint amount0, uint amount1) external returns (uint liquidity, uint realAmount0, uint realAmount1);
    function swap(uint amount0In, uint amount1In) external returns (uint amount0Out, uint amount1Out);
    function burn(uint liquidity) external returns (uint amount0, uint amount1);
    function approve(address spender, uint value) external returns (bool);
}

contract KswapEntrust is MinterRole {
    using SafeMath  for uint;

    uint public contractFee = 0;
    uint public minEntrust = 100*(10**8);
    uint public investRate = 5;
    uint public minMortgage = 1*(10**8);
    uint public maxMortgage = 10000*(10**8);

    string public constant TRANS_FUNCTION = 'transfer(address,uint256)';
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes(TRANS_FUNCTION)));

    event Entrust(address indexed sender, uint liquidity, uint pro, uint usdt, uint totalUsdt, uint leftUsdt);
    event Withdraw(address indexed sender, uint liquidity, uint pro, uint usdt);
    event Mortgage(address indexed sender, uint amount);
    event Redeem(address indexed sender, uint amount);
    event ActiveBonus(address indexed sender);

    mapping(address => uint) public liquidityOf;
    mapping(address => uint) public proOf;
    mapping(address => uint) public usdtOf;
    mapping(address => uint) public bounsOf;
    mapping(address => uint) public mortgageOf;

    address public pairAddress;
    address public proAddress;
    address public usdtAddress;
    ISwapPair public swapPair;

    constructor(address _pairAddress, address _proAddress, address _usdtAddress) public {
        pairAddress = _pairAddress;
        swapPair = ISwapPair(_pairAddress);
        proAddress = _proAddress;
        usdtAddress = _usdtAddress;
    }

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Kswap: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function _safeTransfer(address token, address to, uint value) private {
        bool success = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success, 'Kswap: TRANSFER_FAILED');
    }

    function entrust(uint usdtAmount) external lock {
        require(usdtAmount>=minEntrust, 'Kswap: LESS_THAN_MIN');
        address _proAddress = proAddress;
        address _usdtAddress = usdtAddress;
        IERC20 pro = IERC20(_proAddress);
        IERC20 usdt = IERC20(_usdtAddress);
        require(usdt.transferFrom(msg.sender, address(this), usdtAmount), 'Kswap: AMOUNT_APPROVE_ERROR');
        uint swapAmount = usdtAmount.mul(investRate)/100;
        uint leftUsdtAmount = usdtAmount.sub(swapAmount);
        usdt.approve(pairAddress, usdtAmount);
        (uint proAmount,) = swapPair.swap(0, swapAmount);
        pro.approve(pairAddress, proAmount);
        (uint liquidity, uint realAmount0, uint realAmount1) = swapPair.invest(proAmount, leftUsdtAmount);
        liquidityOf[msg.sender] = liquidityOf[msg.sender].add(liquidity);
        proOf[msg.sender] = proOf[msg.sender].add(proAmount.sub(realAmount0));
        usdtOf[msg.sender] = usdtOf[msg.sender].add(leftUsdtAmount.sub(realAmount1));
        emit Entrust(msg.sender, liquidity, realAmount0, realAmount1, usdtAmount, leftUsdtAmount.sub(realAmount1));
    }

    function withdraw() external lock {

        address _proAddress = proAddress;
        address _usdtAddress = usdtAddress;

        uint liquidity = liquidityOf[msg.sender];
        require(liquidity>0, 'Kswap: INSUFFICIENT_LIQUIDTY');
        liquidityOf[msg.sender] = liquidityOf[msg.sender].sub(liquidity);
        (uint proAmount, uint usdtAmount) = swapPair.burn(liquidity);
        uint leftPro = proOf[msg.sender];
        uint leftUsdt = usdtOf[msg.sender];
        proOf[msg.sender] = proOf[msg.sender].sub(leftPro);
        usdtOf[msg.sender] = usdtOf[msg.sender].sub(leftUsdt);
        _safeTransfer(_proAddress, msg.sender, proAmount.add(leftPro));
        _safeTransfer(_usdtAddress, msg.sender, usdtAmount.add(leftUsdt));
        emit Withdraw(msg.sender, liquidity, proAmount.add(leftPro), usdtAmount.add(leftUsdt));
    }

    function setContractFee(uint _contractFee) external onlyMinter {
        contractFee = _contractFee;
    }

    function activeBonus() external {
        emit ActiveBonus(msg.sender);
    }

    function addBonus(address to, uint value) external onlyMinter {
        bounsOf[to] = bounsOf[to].add(value);
    }

    function getBonus() external {
        address _proAddress = proAddress;
        uint value = bounsOf[msg.sender];
        uint back = value.sub(contractFee);
        bounsOf[msg.sender] = bounsOf[msg.sender].sub(value);
        IERC20(_proAddress).mint(msg.sender, back);
    }

    function editMinEntrust(uint _minEntrust) onlyMinter external {
        minEntrust = _minEntrust;
    }

    function editMinMortgage(uint _minMortgage) onlyMinter external {
        minMortgage = _minMortgage;
    }

    function editMaxMortgage(uint _maxEntrust) onlyMinter external {
        maxMortgage = _maxEntrust;
    }

    function mortgage(uint amount) external {
        address _proAddress = proAddress;
        uint newAmount =  mortgageOf[msg.sender].add(amount);
        require(newAmount>=minMortgage && newAmount<=maxMortgage, 'Kswap: BEYOND_LIMIT');
        require(IERC20(_proAddress).transferFrom(msg.sender, address(this), amount), 'Kswap: AMOUNT_APPROVE_ERROR');
        mortgageOf[msg.sender] = mortgageOf[msg.sender].add(amount);
        emit Mortgage(msg.sender, amount);
    }

    function redeem() external {

        uint mortgageAmount = mortgageOf[msg.sender];
        require(mortgageAmount>0, 'Kswap: INSUFFICIENT_MORTGAGE_AMOUNT');
        address _proAddress = proAddress;
        mortgageOf[msg.sender] =  mortgageOf[msg.sender].sub(mortgageAmount);
        _safeTransfer(_proAddress, msg.sender, mortgageAmount);
        emit Redeem(msg.sender, mortgageAmount);
    }
}