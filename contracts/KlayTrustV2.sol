pragma solidity ^0.6.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./BaseTrust.sol";
import "./klayswap/IKSLP.sol";

contract KlayTrustV2 is BaseTrust {

    constructor(
        string memory _name,
        string memory _symbol,
        address _ksp,
        address _kslp
    ) public BaseTrust(_name, _symbol, _ksp, _kslp) { }

    function deposit(uint256 amountA, uint256 amountB) external virtual override {
        revert();
    }

    function depositKlay(uint256 _amount) external payable virtual override nonReentrant {
        require(msg.value > 0 && _amount > 0, "Deposit must be greater than 0");

        (uint256 beforeKlayInKSLP, uint256 beforeTokenInKSLP) = IKSLP(kslp).getCurrentPool();
        uint256 beforeLP = _balanceKSLP();

        // Deposit underlying assets and Provide liquidity
        IERC20(tokenB).transferFrom(_msgSender(), address(this), _amount);
        _addLiquidity(msg.value, _amount);

        (uint256 afterKlayInKSLP, uint256 afterTokenInKSLP) = IKSLP(kslp).getCurrentPool();
        uint256 afterLP = _balanceKSLP();

        uint256 depositedKlay = afterKlayInKSLP.sub(beforeKlayInKSLP);
        uint256 depositedToken = afterTokenInKSLP.sub(beforeTokenInKSLP);

        // Calcualte vault's increased liquidity and account's remaining tokens
        uint256 remainingKlay = (msg.value).sub(depositedKlay);
        uint256 remainingToken = _amount.sub(depositedToken);
        uint256 increasedLP = afterLP.sub(beforeLP);

        // Calculate pool shares
        uint256 shares = 0;
        if (totalSupply() < 1)
            shares = increasedLP;
        else
            shares = (increasedLP.mul(totalSupply())).div(beforeLP);

        // Return change
        if(remainingToken > 0)
            IERC20(tokenB).transfer(_msgSender(), remainingToken);
        if(remainingKlay > 0)
            msg.sender.transfer(remainingKlay);

        // Mint bToken
        _mint(_msgSender(), shares);
    }

    function withdraw(uint256 _shares) external virtual override nonReentrant {
        require(_shares > 0, "Withdraw must be greater than 0");

        uint256 totalShares = balanceOf(msg.sender);
        require(_shares <= totalShares, "Insufficient balance");

        uint256 totalLP = _balanceKSLP();

        uint256 sharesLP = (totalLP.mul(_shares)).div(totalSupply());

        _burn(msg.sender, _shares);

        (uint256 beforeKlayInKSLP, uint256 beforeTokenInKSLP) = IKSLP(kslp).getCurrentPool();
        _removeLiquidity(sharesLP);
        (uint256 afterKlayInKSLP, uint256 afterTokenInKSLP) = IKSLP(kslp).getCurrentPool();

        uint256 amountKlay = beforeKlayInKSLP.sub(afterKlayInKSLP);
        uint256 amountToken = beforeTokenInKSLP.sub(afterTokenInKSLP);

        IERC20(tokenB).transfer(_msgSender(), amountToken);
        msg.sender.transfer(amountKlay);
    }

    function withdrawKSLP(uint256 _shares) external nonReentrant {
        require(_shares > 0, "Withdraw must be greater than 0");
        require(_shares <= balanceOf(msg.sender), "Insufficient balance");

        uint256 totalLP = _balanceKSLP();
        uint256 sharesLP = (totalLP.mul(_shares)).div(totalSupply());

        _burn(msg.sender, _shares);

        IERC20(kslp).transfer(_msgSender(), sharesLP);
    }
}