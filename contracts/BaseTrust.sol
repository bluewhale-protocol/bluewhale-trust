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


contract BaseTrust is ITrust, ERC20, Ownable, ReentrancyGuard {
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
        address _ksp,
        address _kslp
    ) public ERC20(_name, _symbol, ERC20(_kslp).decimals()) {
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
        if(tokenA != address(0))
            IERC20(tokenA).approve(kslp, uint256(-1));
        
        IERC20(tokenB).approve(kslp, uint256(-1));
        IERC20(ksp).approve(ksp, uint256(-1));
    }

    function estimateSupply(address token, uint256 amount) public view virtual override returns (uint256) {
        require(token == tokenA || token == tokenB);

        uint256 pos = IKSLP(kslp).estimatePos(token, amount);
        uint256 neg = IKSLP(kslp).estimateNeg(token, amount);

        return (pos.add(neg)).div(2);
    }
    
    function estimateRedeem(uint256 shares) public view virtual override returns (uint256, uint256) {
        uint256 totalBWTP = totalSupply();
        require(shares <= totalBWTP);

        (uint256 balanceA, uint256 balanceB) = totalValue();

        uint256 estimatedA = (balanceA.mul(shares)).div(totalBWTP);
        uint256 estimatedB = (balanceB.mul(shares)).div(totalBWTP);

        return (estimatedA, estimatedB);
    }

    //특정 address 소유의 기초자산 잔고
    function valueOf(address account) public view virtual override returns (uint256, uint256){
        uint256 totalBWTP = totalSupply();

        if(totalBWTP == 0)
            return (0, 0);

        uint256 shares = balanceOf(account);

        (uint256 balanceA, uint256 balanceB) = totalValue();
        
        uint256 valueA = (balanceA.mul(shares)).div(totalBWTP);
        uint256 valueB = (balanceB.mul(shares)).div(totalBWTP);

        return (valueA, valueB);
    }


    function totalValue() public view virtual override returns (uint256, uint256) {
        (uint256 balAInTrust, uint256 balBInTrust) = _balanceInTrust();
        (uint256 balAInKSLP, uint256 balBInKSLP) = _balanceInKSLP();

        return (balAInTrust.add(balAInKSLP), balBInTrust.add(balBInKSLP));
    }

    function _tokenABalance() internal view returns (uint256) {
        uint256 balance = (tokenA == address(0))? 
            (payable(address(this))).balance : IERC20(tokenA).balanceOf(address(this));

        return balance;
    }

    function _tokenBBalance() internal view returns (uint256) {
        return IERC20(tokenB).balanceOf(address(this));
    }

    function _balanceInTrust() internal view returns (uint256, uint256){
        uint256 balanceA = _tokenABalance();
        uint256 balanceB = _tokenBBalance();

        return (balanceA, balanceB);
    }

    function _balanceInKSLP() internal view returns (uint256, uint256) {
        uint256 trustLiquidity = _balanceKSLP();
        uint256 totalLiquidity = IERC20(kslp).totalSupply();

        (uint256 poolA, uint256 poolB) = IKSLP(kslp).getCurrentPool();

        uint256 balanceA = (poolA.mul(trustLiquidity)).div(totalLiquidity);
        uint256 balanceB = (poolB.mul(trustLiquidity)).div(totalLiquidity);

        return (balanceA, balanceB);
    }

    function _balanceKSLP() internal view returns (uint256){
        return IERC20(kslp).balanceOf(address(this));
    }

    function _addLiquidity(uint256 _amountA, uint256 _amountB) internal {
        if(tokenA == address(0))
            IKSLP(kslp).addKlayLiquidity{value: _amountA}(_amountB);
        else
            IKSLP(kslp).addKctLiquidity(_amountA, _amountB);
    }

    function _addLiquidityAll() internal {
        uint256 balanceA = _tokenABalance();
        uint256 balanceB = _tokenBBalance();

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
        uint256 totalLP = _balanceKSLP();
        require(_amount <= totalLP);
        
        IKSLP(kslp).removeLiquidity(_amount);
    }

    //KSP 수익실현
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

    //KSP Claim
    function _claim() internal {
        IKSLP(kslp).claimReward();
    }

    //Swap KSP to underlying Assets
    function _swap() internal {
        uint256 earned = IERC20(ksp).balanceOf(address(this));

        if(earned > 0) {
            uint256 balanceA = _tokenABalance();
            uint256 balanceB = _tokenBBalance();

            uint256 balanceABasedKSP = (tokenA == ksp)? 0 : _estimateBasedKSP(tokenA, balanceA);
            uint256 balanceBBasedKSP = (tokenB == ksp)? 0 : _estimateBasedKSP(tokenB, balanceB);

            uint256 netEarned = earned.sub(_teamReward(earned));

            uint256 swapAmount = ((netEarned.sub(balanceABasedKSP)).sub(balanceBBasedKSP)).div(2);
            
            uint256 swapAmountA = swapAmount.add(balanceBBasedKSP);
            uint256 swapAmountB = swapAmount.add(balanceABasedKSP);

            if(swapAmountA > 0)
                _swapKSPToToken(tokenA, swapAmountA);
            if(swapAmountB > 0)
                _swapKSPToToken(tokenB, swapAmountB);
        }
    }

    function _kspTokenPoolExist(address token) internal view returns (bool) {
        try IKSP(ksp).tokenToPool(ksp, token) returns (address pool) {
            return IKSP(ksp).poolExist(pool);
        } catch Error (string memory) {
            return false;
        } catch (bytes memory) {
            return false;
        }
    }

    function _swapKSPToToken(address token, uint256 amount) internal {
        if(token == ksp)
            return;
        
        address[] memory path;
        if(_kspTokenPoolExist(token)){
            path = new address[](0);
        } else {
            path = new address[](1);
            path[0] = address(0);
        }
        
        uint256 least = (_estimateKSPToToken(token, amount).mul(99)).div(100);
        IKSP(ksp).exchangeKctPos(ksp, amount, token, least, path);
    }

    function _estimateBasedKSP(address token, uint256 amount) internal view returns (uint256) {
        require(token == tokenA || token == tokenB);

        if(token == ksp){
            return amount;
        }

        if(token == address(0)){
            return IKSLP(klayKspPool).estimateNeg(token, amount);
        } 
        else if(_kspTokenPoolExist(token)) {
            address kspTokenPool = IKSP(ksp).tokenToPool(ksp, token);
            return IKSLP(kspTokenPool).estimateNeg(token, amount);
        }
        else {
            address klayTokenPool = IKSP(ksp).tokenToPool(address(0), token);

            uint256 estimatedKlay = IKSLP(klayTokenPool).estimateNeg(token, amount);
            uint256 estimatedKSP = IKSLP(klayKspPool).estimateNeg(address(0), estimatedKlay);

            return estimatedKSP;
        }
    }

    function _estimateKSPToToken(address token, uint256 kspAmount) internal view returns (uint256) {
        require(token == tokenA || token == tokenB);

        if(token == ksp){
            return kspAmount;
        }

        if(token == address(0)){
            return IKSLP(klayKspPool).estimatePos(ksp, kspAmount);
        } 
        else if(_kspTokenPoolExist(token)) {
            address kspTokenPool = IKSP(ksp).tokenToPool(ksp, token);
            return IKSLP(kspTokenPool).estimatePos(ksp, kspAmount);
        }
        else {
            address klayTokenPool = IKSP(ksp).tokenToPool(address(0), token);

            uint256 estimatedKlay = IKSLP(klayKspPool).estimatePos(ksp, kspAmount);
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

    function setFee(uint256 _fee) public onlyOwner {
        require(0 <= _fee && _fee <= 10000);
        require(_fee != fee);
        emit FeeChanged(fee, _fee);
        fee = _fee;
    }

    function setTeamWallet(address _teamWallet) public onlyOwner {
        require(_teamWallet != address(0));
        require(_teamWallet != teamWallet);
        emit TeamWalletChanged(teamWallet, _teamWallet);
        teamWallet = _teamWallet;
    }

    function deposit(uint256 amountA, uint256 amountB) external virtual override { }

    function depositKlay(uint256 _amount) external payable virtual override { }

    function withdraw(uint256 _shares) external virtual override { }
}