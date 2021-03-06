pragma solidity ^0.6.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "./IKSLPTrust.sol";
import "./IKSLP.sol";
import "./IKSP.sol";


contract KSLPTrust is IKSLPTrust, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public ksp;
    address public kslp;

    address public tokenA;
    address public tokenB;

    address public klayKspPool;

    uint256 public fee;
    address public teamWallet;

    uint256 public version = 1;

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

    function estimateRedeem(uint256 shares) public view virtual override returns (uint256) {
        uint256 totalBWTP = totalSupply();
        require(shares <= totalBWTP, "Requested shares exceeded total supply.");

        uint256 totalKSLP = kslpInTrust();

        uint256 estimated = (totalKSLP.mul(shares)).div(totalBWTP);

        return estimated;
    }

    function kslpInTrust() public view returns (uint256) {
        return IERC20(kslp).balanceOf(address(this));
    }

    function deposit(uint256 _amount) external virtual override nonReentrant {
        require(_amount > 0, "Deposit must be greater than 0");

        uint256 totalKSLP = kslpInTrust();

        IERC20(kslp).transferFrom(_msgSender(), address(this), _amount);

        uint256 shares = 0;
        if (totalSupply() < 1) 
            shares = _amount;
        else
            shares = (_amount.mul(totalSupply())).div(totalKSLP);

        // Mint bToken
        _mint(_msgSender(), shares);
    }

    function withdraw(uint256 _shares) external virtual override nonReentrant {
        require(_shares > 0, "Withdraw must be greater than 0");
        require(_shares <= balanceOf(msg.sender), "Insufficient balance");

        uint256 totalKSLP = kslpInTrust();

        uint256 sharesKSLP = (totalKSLP.mul(_shares)).div(totalSupply());

        _burn(msg.sender, _shares);

        IERC20(kslp).transfer(_msgSender(), sharesKSLP);
    }

    //?????? address ????????? LP ??????
    function kslpOf(address account) public view virtual override returns (uint256){
        uint256 totalBWTP = totalSupply();

        if(totalBWTP == 0)
            return 0;

        uint256 totalShares = balanceOf(account);
        uint256 totalKSLP = kslpInTrust();

        uint256 sharesKSLP = (totalKSLP.mul(totalShares)).div(totalBWTP);

        return sharesKSLP;
    }

    //?????? address ????????? ???????????? ??????
    function valueOf(address account) public view virtual override returns (uint256, uint256){
        uint256 totalBWTP = totalSupply();

        if(totalBWTP == 0)
            return (0, 0);

        uint256 totalShares = balanceOf(account);
        (uint256 totalTokenA, uint256 totalTokenB) = totalValue();

        uint256 balanceA = (totalTokenA.mul(totalShares)).div(totalBWTP);
        uint256 balanceB = (totalTokenB.mul(totalShares)).div(totalBWTP);

        return (balanceA, balanceB);
    }

    function totalValue() public view virtual override returns (uint256, uint256) {
        uint256 totalKSLP = kslpInTrust();
        uint256 kslpTotalSupply = IERC20(kslp).totalSupply();

        (uint256 poolA, uint256 poolB) = IKSLP(kslp).getCurrentPool();

        uint256 balanceA = (poolA.mul(totalKSLP)).div(kslpTotalSupply);
        uint256 balanceB = (poolB.mul(totalKSLP)).div(kslpTotalSupply);

        return (balanceA, balanceB);
    }

    //KSP ????????????
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

    function _tokenABalance() internal view returns (uint256) {
        uint256 balance = (tokenA == address(0))? 
            (payable(address(this))).balance : IERC20(tokenA).balanceOf(address(this));

        return balance;
    }

    function _tokenBBalance() internal view returns (uint256) {
        return IERC20(tokenB).balanceOf(address(this));
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
        require(token == tokenA || token == tokenB, "Invalid token address");

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
        require(token == tokenA || token == tokenB, "Invalid token address");

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

    function _addLiquidity(uint256 _amountA, uint256 _amountB) internal {
        IKSLP(kslp).addKctLiquidity(_amountA, _amountB);
    }

    function _addLiquidityAll() internal {
        uint256 balanceA = _tokenABalance();
        uint256 balanceB = _tokenBBalance();

        if(balanceA > 0 && balanceB > 0){
            uint256 estimatedA = _estimateSupply(tokenB, balanceB);
            uint256 estimatedB = _estimateSupply(tokenA, balanceA);

            if(balanceB >= estimatedB)
                _addLiquidity(balanceA, estimatedB);
            else
                _addLiquidity(estimatedA, balanceB);
        }
    }

    function _estimateSupply(address token, uint256 amount) internal view returns (uint256) {
        require(token == tokenA || token == tokenB, "Invalid token address");

        uint256 pos = IKSLP(kslp).estimatePos(token, amount);
        uint256 neg = IKSLP(kslp).estimateNeg(token, amount);

        return (pos.add(neg)).div(2);
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