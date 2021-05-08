pragma solidity ^0.6.0;

interface IKctTrust {

    function deposit(uint256 amountA, uint256 amountB) external;

    function withdraw(uint256 shares) external;

    function estimateSupply(address token, uint256 amount) external view returns (uint256);

    function estimateRedeem(uint256 amount) external view returns (uint256, uint256);

    function valueOf(address account) external view returns (uint256, uint256);

    function totalValue() external view returns (uint256, uint256);

    function rebalance() external;

}