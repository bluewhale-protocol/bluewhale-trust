pragma solidity ^0.6.0;

interface IKSP {
    function exchangeKlayPos(address token, uint256 amount, address[] memory path) external payable;
    function exchangeKctPos(address tokenA, uint256 amountA, address tokenB, uint256 amountB, address[] memory path) external;
    function exchangeKlayNeg(address token, uint256 amount, address[] memory path) external payable;
    function exchangeKctNeg(address tokenA, uint256 amountA, address tokenB, uint256 amountB, address[] memory path) external;
    function tokenToPool(address tokenA, address tokenB) external view returns (address);
}
