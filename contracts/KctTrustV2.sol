pragma solidity ^0.6.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./BaseTrust.sol";
import "./klayswap/IKSLP.sol";

contract KctTrustV2 is BaseTrust {

    constructor(
        string memory _name,
        string memory _symbol,
        address _ksp,
        address _kslp
    ) public BaseTrust(_name, _symbol, _ksp, _kslp) { }

    function depositKlay(uint256 amount) external payable virtual override {
        revert();
    }

    function deposit(uint256 _amountA, uint256 _amountB) external virtual override nonReentrant {
        require(_amountA > 0 && _amountB > 0, "Deposit must be greater than 0");

        (uint256 beforeAInKSLP, uint256 beforeBInKSLP) = IKSLP(kslp).getCurrentPool();
        uint256 beforeLP = _balanceKSLP();

        // Deposit underlying assets and Provide liquidity
        IERC20(tokenA).transferFrom(_msgSender(), address(this), _amountA);
        IERC20(tokenB).transferFrom(_msgSender(), address(this), _amountB);
        _addLiquidity(_amountA, _amountB);

        (uint256 afterAInKSLP, uint256 afterBInKSLP) = IKSLP(kslp).getCurrentPool();
        uint256 afterLP = _balanceKSLP();

        uint256 depositedA = afterAInKSLP.sub(beforeAInKSLP);
        uint256 depositedB = afterBInKSLP.sub(beforeBInKSLP);

        // Calcualte trust's increased liquidity and account's remaining tokens
        uint256 remainingA = _amountA.sub(depositedA);
        uint256 remainingB = _amountB.sub(depositedB);
        uint256 increasedLP = afterLP.sub(beforeLP);

        // Calculate pool shares
        uint256 shares = 0;
        if (totalSupply() < 1) 
            shares = increasedLP;
        else
            shares = (increasedLP.mul(totalSupply())).div(beforeLP);

        // Return change
        if(remainingA > 0)
            IERC20(tokenA).transfer(_msgSender(), remainingA);
        if(remainingB > 0)
            IERC20(tokenB).transfer(_msgSender(), remainingB);

        // Mint bToken
        _mint(_msgSender(), shares);
    }

    function withdraw(uint256 _shares) external virtual override nonReentrant {
        require(_shares > 0, "Withdraw must be greater than 0");
        require(_shares <= balanceOf(msg.sender), "Insufficient balance");

        uint256 totalLP = _balanceKSLP();

        uint256 sharesLP = (totalLP.mul(_shares)).div(totalSupply());

        _burn(msg.sender, _shares);

        (uint256 beforeAInKSLP, uint256 beforeBInKSLP) = IKSLP(kslp).getCurrentPool();
        _removeLiquidity(sharesLP);
        (uint256 afterAInKSLP, uint256 afterBInKSLP) = IKSLP(kslp).getCurrentPool();

        uint256 withdrawalA = beforeAInKSLP.sub(afterAInKSLP);
        uint256 withdrawalB = beforeBInKSLP.sub(afterBInKSLP);

        IERC20(tokenA).transfer(_msgSender(), withdrawalA);
        IERC20(tokenB).transfer(_msgSender(), withdrawalB);
    }
}