pragma solidity ^0.6.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";

import "./ITrust.sol";
import "./klayswap/IKSLP.sol";
import "./klayswap/IKSP.sol";

contract KlayTrust is ITrust, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public tokenA; // 0x0
    address public tokenB; // token address for KLAY-[token] LP

    address public klayKspPool; //klayswap KLAY-KSP LP address

    address public ksp; // KSP address
    address public kslp; // klayswap KLAY-[token] LP address

    uint256 public fee;
    address public teamWallet; 

    event FeeChanged(uint256 beforeFee, uint256 newFee);
    event TeamWalletChanged(address beforeWallet, address newWallet);


    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _ksp,
        address _kslp
    ) public ERC20(_name, _symbol, _decimals) {
        ksp = _ksp;
        kslp = _kslp;
        tokenA = IKSLP(kslp).tokenA();
        tokenB = IKSLP(kslp).tokenB();

        klayKspPool = IKSP(ksp).tokenToPool(tokenA, ksp);
        
        setTeamWallet(_msgSender());
        setFee(100);

        _approveToken();
    }

    receive () payable external {}

    function _approveToken() internal {
        IERC20(tokenB).approve(kslp, uint256(-1));
        IERC20(ksp).approve(ksp, uint256(-1));
    }

    function estimateSupply(address _token, uint256 _amount) public view virtual override returns (uint256) {
        require(_token == tokenA || _token == tokenB, "Invalid token address");

        uint256 pos = IKSLP(kslp).estimatePos(_token, _amount);
        uint256 neg = IKSLP(kslp).estimateNeg(_token, _amount);

        return (pos.add(neg)).div(2);
    }
    
    function estimateRedeem(uint256 shares) public view virtual override returns (uint256, uint256) {
        uint256 totalShares = totalSupply();
        require(shares <= totalShares, "Requested shares exceeded total supply.");

        (uint256 balanceKlay, uint256 balanceToken) = totalValue();

        uint256 estimatedKlay = (balanceKlay.mul(shares)).div(totalShares);
        uint256 estimatedToken = (balanceToken.mul(shares)).div(totalShares);

        return (estimatedKlay, estimatedToken);
    }

    function deposit(uint256 amountA, uint256 amountB) external virtual override {
        revert();
    }

    function depositKlay(uint256 _amount) external payable virtual override nonReentrant {
        require(msg.value > 0 && _amount > 0, "Deposit must be greater than 0");

        (uint256 beforeKlay, uint256 beforeToken) = _balanceInTrust();
        beforeKlay = beforeKlay.sub(msg.value);
        uint256 beforeLP = _balanceLPTokenInKSLP();

        // Deposit underlying assets and Provide liquidity
        IERC20(tokenB).transferFrom(_msgSender(), address(this), _amount);
        _addLiquidity(msg.value, _amount);

        (uint256 afterKlay, uint256 afterToken) = _balanceInTrust();
        uint256 afterLP = _balanceLPTokenInKSLP();

        // Calcualte vault's increased liquidity and account's remaining tokens
        uint256 remainingKlay = afterKlay.sub(beforeKlay);
        uint256 remainingToken = afterToken.sub(beforeToken);
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

        uint256 totalLP = _balanceLPTokenInKSLP();

        uint256 sharesLP = (totalLP.mul(_shares)).div(totalSupply());

        _burn(msg.sender, _shares);

        (uint256 beforeKlay, uint256 beforeToken) = _balanceInTrust();
        _removeLiquidity(sharesLP);
        (uint256 afterKlay, uint256 afterToken) = _balanceInTrust();

        uint256 amountKlay = afterKlay.sub(beforeKlay);
        uint256 amountToken = afterToken.sub(beforeToken);

        IERC20(tokenB).transfer(_msgSender(), amountToken);
        msg.sender.transfer(amountKlay);
    }

    function valueOf(address account) public view virtual override returns (uint256, uint256){
        uint256 totalShares = totalSupply();

        if(totalShares == 0)
            return (0, 0);

        uint256 shares = balanceOf(account);

        (uint256 balanceKlay, uint256 balanceToken) = totalValue();
        
        uint256 a = (balanceKlay.mul(shares)).div(totalShares);
        uint256 b = (balanceToken.mul(shares)).div(totalShares);

        return (a, b);
    }

    function totalValue() public view virtual override returns (uint256, uint256) {
        (uint256 balKlayInTrust, uint256 balTokenInTrust) = _balanceInTrust();
        (uint256 balKlayInKSLP, uint256 balTokenInKSLP) = _balanceInKSLP();

        return (balKlayInTrust.add(balKlayInKSLP), balTokenInTrust.add(balTokenInKSLP));
    }

    function _addLiquidity(uint256 _amountKlay, uint256 _amountToken) internal {
        IKSLP(kslp).addKlayLiquidity{value: _amountKlay}(_amountToken);
    }

    function _addLiquidityAll() internal {
        uint256 balanceKlay = (payable(address(this))).balance;
        uint256 balanceToken = IERC20(tokenB).balanceOf(address(this));

        if(balanceKlay > 0 && balanceToken > 0){
            uint256 estimatedKlay = estimateSupply(tokenB, balanceToken);
            uint256 estimatedToken = estimateSupply(tokenA, balanceKlay);

            if(balanceToken >= estimatedToken)
                _addLiquidity(balanceKlay, estimatedToken);
            else
                _addLiquidity(estimatedKlay, balanceToken);
        }
    }

    function _removeLiquidity(uint256 _amount) internal {
        uint256 totalLP = _balanceLPTokenInKSLP();
        require(_amount <= totalLP, "Required amount exceed balance");
        
        IKSLP(kslp).removeLiquidity(_amount);
    }

    function rebalance() public virtual override onlyOwner {
        _claim();
        _swap();
        _addLiquidityAll();
    }


    function claim() public onlyOwner {
        _claim();
    }

    function swap() public onlyOwner {
        _swap();
    }

    function addLiquidityAll() public onlyOwner {
        _addLiquidityAll();
    }


    function _claim() internal {
        IKSLP(kslp).claimReward();
    }

    function _swap() internal {
        uint256 earned = IERC20(ksp).balanceOf(address(this));

        if(earned > 0){
            uint256 balanceA = (payable(address(this))).balance; // Klay balance
            uint256 balanceB = IERC20(tokenB).balanceOf(address(this));

            uint256 balanceABasedKSP = _estimateBasedKSP(tokenA, balanceA);
            uint256 balanceBBasedKSP = _estimateBasedKSP(tokenB, balanceB);

            uint256 netEarned = earned.sub(_teamReward(earned));

            if(tokenB == ksp)
                balanceBBasedKSP = 0;

            uint256 swapAmount = ((netEarned.sub(balanceABasedKSP)).sub(balanceBBasedKSP)).div(2);
            
            uint256 swapAmountA = swapAmount.add(balanceBBasedKSP);
            uint256 swapAmountB = swapAmount.add(balanceABasedKSP);

            if(swapAmountA > 0){
                address[] memory path = new address[](0);
                _swapKSPToToken(tokenA, swapAmountA, path);
            }
            if(swapAmountB > 0){
                address[] memory path = new address[](1);
                path[0] = address(0);
                _swapKSPToToken(tokenB, swapAmountB, path);
            }
        }
    }

    function _swapKSPToToken(address token, uint256 amount, address[] memory path) internal {
        if(token == ksp)
            return;
        
        uint256 least = (_estimateKSPToToken(token, amount).mul(99)).div(100);
        IKSP(ksp).exchangeKctPos(ksp, amount, token, least, path);
    }

    function _estimateBasedKSP(address token, uint256 amount) internal view returns (uint256) {
        require(token == tokenA || token == tokenB, "Invalid token address");

        if(token == ksp){
            return amount;
        }

        if(token == address(0)){
            uint256 estimatedKSP = IKSLP(klayKspPool).estimateNeg(token, amount);

            return estimatedKSP;
        } else {
            address klayTokenPool = IKSP(ksp).tokenToPool(address(0), token);

            uint256 estimatedKlay = IKSLP(klayTokenPool).estimateNeg(token, amount);
            uint256 estimatedKSP = IKSLP(klayKspPool).estimateNeg(address(0), estimatedKlay);

            return estimatedKSP;
        }
    }

    function _estimateKSPToToken(address token, uint256 kspAmount) internal view returns (uint256) {
        require(token == tokenA || token == tokenB, "Invalid token address");

        if(token == ksp){
            return kspAmount;
        }

        uint256 estimatedKlay = IKSLP(klayKspPool).estimatePos(ksp, kspAmount);

        if(token == address(0)){
            return estimatedKlay;
        } else {
            address klayTokenPool = IKSP(ksp).tokenToPool(address(0), token);
            uint256 estimatedToken = IKSLP(klayTokenPool).estimatePos(address(0), estimatedKlay);
            return estimatedToken;
        }
    }

    function _teamReward(uint256 earned) internal returns (uint256) {
        uint256 reward = (earned.mul(fee)).div(10000);

        address payable owner = payable(owner());
        uint256 ownerKlay = owner.balance; 

        //For transaction call fee
        if(ownerKlay < 3 ether) {
            uint256 estimated = IKSLP(klayKspPool).estimatePos(ksp, reward);
            uint256 least = (estimated.mul(99)).div(100);

            uint256 beforeKlay = (payable(address(this))).balance;
            address[] memory path = new address[](0);
            IKSP(ksp).exchangeKctPos(ksp, reward, address(0), least, path);
            uint256 afterKlay = (payable(address(this))).balance;

            uint256 amount = afterKlay.sub(beforeKlay);
            owner.transfer(amount);

            return reward;
        }
        else if(teamWallet != address(0)) {
            IERC20(ksp).transfer(teamWallet, reward);
            return reward;
        }

        return 0;
    }

    function _balanceInTrust() internal view returns (uint256, uint256){
        uint256 balanceKlay = (payable(address(this))).balance;
        uint256 balanceToken = IERC20(tokenB).balanceOf(address(this));

        return (balanceKlay, balanceToken);
    }

    function _balanceInKSLP() internal view returns (uint256, uint256) {
        uint256 liquidity = _balanceLPTokenInKSLP();
        uint256 totalLiquidity = IERC20(kslp).totalSupply();

        (uint256 poolKlay, uint256 poolToken) = IKSLP(kslp).getCurrentPool();

        uint256 balanceKlay = (poolKlay.mul(liquidity)).div(totalLiquidity);
        uint256 balanceToken = (poolToken.mul(liquidity)).div(totalLiquidity);

        return (balanceKlay, balanceToken);
    }

    function _balanceLPTokenInKSLP() internal view returns (uint256){
        return IERC20(kslp).balanceOf(address(this));
    }

    function setFee(uint256 _fee) public onlyOwner {
        require(0 <= _fee && _fee <= 10000, "The fee must be between 0 and 10000");
        require(_fee != fee, "Can't set the same value as before");
        emit FeeChanged(fee, _fee);
        fee = _fee;
    }

    function setTeamWallet(address _teamWallet) public onlyOwner {
        require(_teamWallet != address(0), "Team wallet address can't be 0x0");
        require(_teamWallet != teamWallet, "Can't set the same value as before");
        emit TeamWalletChanged(teamWallet, _teamWallet);
        teamWallet = _teamWallet;
    }
}