pragma solidity ^0.4.23;

import './KswapERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';

contract KswapPair is KswapERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    string public constant TRANS_FUNCTION = 'transfer(address,uint256)';
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes(TRANS_FUNCTION)));

    address public token0;
    address public token1;
    uint public feeRate = 30;
    uint public totalFee = 0;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32  private blockTimestampLast;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Kswap: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    function _safeTransfer(address token, address to, uint value) private {
        bool success = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success, 'Kswap: TRANSFER_FAILED');
    }

    event Invest(address indexed sender, uint liquidity, uint amount0, uint amount1);
    event Burn(address indexed sender, uint liquidity, uint amount0, uint amount1);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        uint feeRate
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1) public {
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'Kswap: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function invest(uint amount0, uint amount1) external lock returns (uint liquidity, uint realAmount0, uint realAmount1) {
        require(amount0>0 && amount1>0, 'Kswap: INSUFFICIENT_INVEST_AMOUNT');

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;

        uint _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1));
            realAmount0 = amount0;
            realAmount1 = amount1;
        } else {
            uint liquidity1 = amount0.mul(_totalSupply) / _reserve0;
            uint liquidity2 = amount1.mul(_totalSupply) / _reserve1;
            liquidity = Math.min(liquidity1, liquidity2);
            if (liquidity1>liquidity2){
                realAmount0 = amount1.mul(_reserve0) / _reserve1;
                realAmount1 = amount1;
            }
            else {
                realAmount0 = amount0;
                realAmount1 = amount0.mul(_reserve1)/_reserve0;
            }
        }

        require(liquidity > 0, 'Kswap: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(msg.sender, liquidity);
        require(IERC20(_token0).transferFrom(msg.sender, address(this), realAmount0), 'Kswap: AMOUNT0_APPROVE_ERROR');
        require(IERC20(_token1).transferFrom(msg.sender, address(this), realAmount1), 'Kswap: AMOUNT1_APPROVE_ERROR');
        _update(realAmount0.add(_reserve0), realAmount1.add(_reserve1), _reserve0, _reserve1);
        emit Invest(msg.sender, liquidity, realAmount0, realAmount1);
    }

    function burn(uint liquidity) external lock returns (uint amount0, uint amount1) {

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;

        uint _totalSupply = totalSupply;
        require(_totalSupply>0, 'Kswap: INSUFFICIENT_TOTAL_SUPPLY');
        _burn(msg.sender, liquidity);
        amount0 = liquidity.mul(_reserve0) / _totalSupply;
        amount1 = liquidity.mul(_reserve1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, 'Kswap: INSUFFICIENT_LIQUIDITY_BURNED');

        _safeTransfer(_token0, msg.sender, amount0);
        _safeTransfer(_token1, msg.sender, amount1);
        require(_reserve0-amount0<=_reserve0);
        require(_reserve1-amount1<=_reserve1);

        _update(_reserve0-amount0, _reserve1-amount1, _reserve0, _reserve1);
        emit Burn(msg.sender, liquidity, amount0, amount1);
    }

    function swap(uint amount0In, uint amount1In) external lock returns (uint amount0Out, uint amount1Out) {
        require(amount0In > 0 || amount1In > 0, 'Kswap: INSUFFICIENT_INPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();


        uint fee;
        uint _feeRate = feeRate;
        {
            address _token0 = token0;
            address _token1 = token1;
            if (amount0In > 0) { // baseSymbol
                require(amount1In==0, 'Kswap: INSUFFICIENT_INPUT_AMOUNT');
                require(IERC20(_token0).transferFrom(msg.sender, address(this), amount0In), 'Kswap: AMOUNT0_APPROVE_ERROR');
                amount1Out = uint(_reserve1) - uint(_reserve1)*_reserve0/(_reserve0+amount0In) - 1;
                fee = amount1Out.mul(_feeRate)/10000;
                _safeTransfer(_token1, msg.sender, amount1Out.sub(fee));
            }
            if (amount1In > 0) {
                require(amount0In==0, 'Kswap: INSUFFICIENT_INPUT_AMOUNT');
                require(IERC20(_token1).transferFrom(msg.sender, address(this), amount1In), 'Kswap: AMOUNT1_APPROVE_ERROR');
                fee = amount1In.mul(_feeRate)/10000;
                amount0Out = uint(_reserve0) - uint(_reserve1)*_reserve0/(_reserve1+amount1In.sub(fee)) - 1;
                _safeTransfer(_token0, msg.sender, amount0Out);
            }
        }
        totalFee += fee;

        require(amount0Out > 0 || amount1Out > 0, 'Kswap: INSUFFICIENT_OUTPUT_AMOUNT');
        uint balance0 = uint(_reserve0).sub(amount0Out).add(amount0In);
        uint balance1 = uint(_reserve1).sub(amount1Out).add(amount1In);
        if (amount1In > 0) {
            balance1 = balance1.sub(fee);
        }
        require(balance1.mul(balance0)>=uint(_reserve0).mul(uint(_reserve1)), "Kswap: ERROR_RESULT");

        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'Kswap: INSUFFICIENT_LIQUIDITY');

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, fee);
    }

    function skim(address to) external onlyMinter lock {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    function setFeeRate(uint _feeRate) external onlyMinter {
        require(_feeRate<=30);
        feeRate = _feeRate;
    }

    function transFee(address to) external onlyMinter lock {
        require(totalFee>0);
        address _token1 = token1;
        _safeTransfer(_token1, to, totalFee);
        totalFee = 0;
    }
}