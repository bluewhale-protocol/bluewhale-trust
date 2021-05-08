pragma solidity ^0.6.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "./IKctTrust.sol";
import "./klayswap/IKSLP.sol";
import "./klayswap/IKSP.sol";


contract KctTrust is IKctTrust, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public tokenA;
    address public tokenB;

    address public klayKspPool;

    address public ksp;
    address public kslp;

    uint256 public fee;
    address public teamWallet;

    event FeeChanged(uint256 previousFee, uint256 newFee);
    event TeamWalletChanged(address previousWallet, address newWallet);

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

        klayKspPool = IKSP(ksp).tokenToPool(address(0), ksp);
        
        setTeamWallet(_msgSender());
        setFee(100);

        _approveToken();
    }

    receive () payable external {}

    function _approveToken() internal {
        IERC20(tokenA).approve(kslp, uint256(-1));
        IERC20(tokenB).approve(kslp, uint256(-1));
        IERC20(ksp).approve(ksp, uint256(-1));
    }

    function estimateSupply(address token, uint256 amount) public view virtual override returns (uint256) {
        require(token == tokenA || token == tokenB, "Invalid token address");

        uint256 pos = IKSLP(kslp).estimatePos(token, amount);
        uint256 neg = IKSLP(kslp).estimateNeg(token, amount);

        return (pos.add(neg)).div(2);
    }
    
    function estimateRedeem(uint256 shares) public view virtual override returns (uint256, uint256) {
        uint256 totalLiquidity = totalSupply();
        require(shares <= totalLiquidity, "Requested shares exceeded total supply.");

        (uint256 balanceA, uint256 balanceB) = totalValue();

        uint256 estimatedA = (balanceA.mul(shares)).div(totalLiquidity);
        uint256 estimatedB = (balanceB.mul(shares)).div(totalLiquidity);

        return (estimatedA, estimatedB);
    }

    function deposit(uint256 _amountA, uint256 _amountB) external virtual override nonReentrant {
        require(_amountA > 0 && _amountB > 0, "Deposit must be greater than 0");

        (uint256 beforeA, uint256 beforeB) = _balanceInTrust();
        uint256 beforeLP = _balanceLPTokenInKSLP();

        // Deposit underlying assets and Provide liquidity
        IERC20(tokenA).transferFrom(_msgSender(), address(this), _amountA);
        IERC20(tokenB).transferFrom(_msgSender(), address(this), _amountB);
        _addLiquidity(_amountA, _amountB);

        (uint256 afterA, uint256 afterB) = _balanceInTrust();
        uint256 afterLP = _balanceLPTokenInKSLP();

        // Calcualte trust's increased liquidity and account's remaining tokens
        uint256 remainingA = afterA.sub(beforeA);
        uint256 remainingB = afterB.sub(beforeB);
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

        uint256 totalShares = balanceOf(msg.sender);
        require(_shares <= totalShares, "Insufficient balance");

        uint256 totalLP = _balanceLPTokenInKSLP();

        uint256 sharesLP = (totalLP.mul(_shares)).div(totalSupply());

        _burn(msg.sender, _shares);

        (uint256 beforeA, uint256 beforeB) = _balanceInTrust();
        _removeLiquidity(sharesLP);
        (uint256 afterA, uint256 afterB) = _balanceInTrust();

        uint256 withdrawalA = afterA.sub(beforeA);
        uint256 withdrawalB = afterB.sub(beforeB);

        IERC20(tokenA).transfer(_msgSender(), withdrawalA);
        IERC20(tokenB).transfer(_msgSender(), withdrawalB);
    }

    function valueOf(address account) public view virtual override returns (uint256, uint256){
        uint256 total = totalSupply();

        if(total == 0)
            return (0, 0);

        uint256 shares = balanceOf(account);

        (uint256 balanceA, uint256 balanceB) = totalValue();
        
        uint256 a = (balanceA.mul(shares)).div(total);
        uint256 b = (balanceB.mul(shares)).div(total);

        return (a, b);
    }


    function totalValue() public view virtual override returns (uint256, uint256) {
        (uint256 balAInTrust, uint256 balBInTrust) = _balanceInTrust();
        (uint256 balAInKSLP, uint256 balBInKSLP) = _balanceInKSLP();

        return (balAInTrust.add(balAInKSLP), balBInTrust.add(balBInKSLP));
    }

    function _addLiquidity(uint256 _amountA, uint256 _amountB) internal {
        IKSLP(kslp).addKctLiquidity(_amountA, _amountB);
    }

    function _addLiquidityAll() internal {
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));

        if(balanceA > 0 && balanceB > 0){
            uint256 estimatedA = estimateSupply(tokenB, balanceB);
            uint256 estimatedB = estimateSupply(tokenA, balanceA);

            if(balanceB >= estimatedB)
                _addLiquidity(balanceA, estimatedB);
            else
                _addLiquidity(estimatedA, balanceB);
        }
    }

    function _removeLiquidity(uint256 _amount) internal {
        uint256 totalLP = _balanceLPTokenInKSLP();
        require(_amount <= totalLP, "Requested amount exceed balance");
        
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
            address[] memory path = new address[](1);
            path[0] = address(0);

            uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
            uint256 balanceB = IERC20(tokenB).balanceOf(address(this));

            uint256 balanceABasedKSP = _estimateBasedKSP(tokenA, balanceA);
            uint256 balanceBBasedKSP = _estimateBasedKSP(tokenB, balanceB);

            uint256 netEarned = earned.sub(_teamReward(earned));

            uint256 swapAmount = ((netEarned.sub(balanceABasedKSP)).sub(balanceBBasedKSP)).div(2);
            
            uint256 swapAmountA = swapAmount.add(balanceBBasedKSP);
            uint256 swapAmountB = swapAmount.add(balanceABasedKSP);

            if(swapAmountA > 0){
                uint256 least = (_estimateKSPToToken(tokenA, swapAmountA).mul(99)).div(100);
                IKSP(ksp).exchangeKctPos(ksp, swapAmountA, tokenA, least, path); 
            }
            if(swapAmountB > 0){
                uint256 least = (_estimateKSPToToken(tokenB, swapAmountB).mul(99)).div(100);
                IKSP(ksp).exchangeKctPos(ksp, swapAmountB, tokenB, least, path); 
            }
        }
    }

    function _estimateBasedKSP(address token, uint256 amount) internal view returns (uint256) {
        require(token == tokenA || token == tokenB, "Invalid token address");

        address klayTokenPool = IKSP(ksp).tokenToPool(address(0), token);

        uint256 estimatedKlay = IKSLP(klayTokenPool).estimateNeg(token, amount);
        uint256 estimatedKSP = IKSLP(klayKspPool).estimateNeg(address(0), estimatedKlay);

        return estimatedKSP;
    }

    function _estimateKSPToToken(address token, uint256 kspAmount) internal view returns (uint256) {
        require(token == tokenA || token == tokenB, "Invalid token address");

        address klayTokenPool = IKSP(ksp).tokenToPool(address(0), token);

        uint256 estimatedKlay = IKSLP(klayKspPool).estimatePos(ksp, kspAmount);
        uint256 estimatedToken = IKSLP(klayTokenPool).estimatePos(address(0), estimatedKlay);

        return estimatedToken;
    }

    function _teamReward(uint256 earned) internal returns (uint256) {
        uint256 reward = (earned.mul(fee)).div(10000);

        address payable owner = payable(owner());
        uint256 ownerKlay = owner.balance; 

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
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));

        return (balanceA, balanceB);
    }

    function _balanceInKSLP() internal view returns (uint256, uint256) {
        uint256 liquidity = _balanceLPTokenInKSLP();
        uint256 totalLiquidity = IERC20(kslp).totalSupply();

        (uint256 poolA, uint256 poolB) = IKSLP(kslp).getCurrentPool();

        uint256 balanceA = (poolA.mul(liquidity)).div(totalLiquidity);
        uint256 balanceB = (poolB.mul(liquidity)).div(totalLiquidity);

        return (balanceA, balanceB);
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