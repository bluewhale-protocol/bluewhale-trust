# KlayTrust Security Report

본 보고서는 Bluewhale의 KlayTrust 스마트 컨트랙트에 대한 잠재적 취약점 존재 여부 등 보안성 검증을 위해 Bluewhale 프로젝트팀에 의해 작성되었습니다. Bluewhale 프로젝트팀은 스마트 컨트랙트 전문 감사(Audit) 업체가 아니므로 스마트 컨트랙트에 대한 보안적 무결성을 완벽히 보장하지 않습니다. 따라서, Trust 스마트 컨트랙트 사용자는 본 보고서를 참고하여 스마트 컨트랙트의 잠재적 위험성을 직접 검증해야 합니다.



## 문서 개정 이력

| 개정 번호 | 개정 일자  | 구분      | 개정 내용 |
| --------- | ---------- | --------- | --------- |
| KLTRU-001 | 2021-05-09 | 신규 작성 | 초안 작성 |





## 검증 대상

* [KlayTrust.sol](../../contracts/KlayTrust.sol)
  * ITrust.sol
  * klayswap/IKSLP.sol
  * klayswap/IKSP.sol





## 권한별 상태 변환 함수 접근 범위

**권한 한정자** 

* onlyOwner - [Ownable.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol)

```Solidity
modifier onlyOwner() {
    require(owner() == _msgSender(), "Ownable: caller is not the owner");
    _;
}
```



**함수 접근 범위**

* onlyOwner
  * rebalance()
  * claim()
  * swap()
  * addLiquidityAll()
* Public
  * deposit()
  * withdraw()





## 보안성 검증

**보안성 검증 항목**

* Re-Entrancy
* Arithmetic Overflow and Underflow
* Self Destruct
* Accessing Private Data
* Delegatecall
* Source of Reandomness
* Denial of Service
* Phishing with tx.origin
* Hiding Malicious Code with External Contract
* Front Running
* Block Timestamp Manipulation
* Signature Replay



### Re-Entrancy

**방지 기법**

* 재진입을 공격을 방지하는 한정자 사용: (**[ReentrancyGuard](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol)**) nonReentrant
* 외부 주소 호출(Transfer) 전 모든 상태 변경 처리



**`depositKlay()`**

```
function depositKlay(
	uint256 _amount
) external payable virtual override nonReentrant {
  require(_amountA > 0 && _amountB > 0, "Deposit must be greater than 0");

  (uint256 beforeKlay, uint256 beforeToken) = _balanceInTrust();
  beforeKlay = beforeKlay.sub(msg.value);
  uint256 beforeLP = _balanceLPTokenInKSLP();

  IERC20(tokenB).transferFrom(_msgSender(), address(this), _amount);
  _addLiquidity(msg.value, _amount);

  (uint256 afterKlay, uint256 afterToken) = _balanceInTrust();
  uint256 afterLP = _balanceLPTokenInKSLP();

  uint256 remainingKlay = afterKlay.sub(beforeKlay);
  uint256 remainingToken = afterToken.sub(beforeToken);
  uint256 increasedLP = afterLP.sub(beforeLP);

  uint256 shares = 0;
  if (totalSupply() < 1)
  	shares = increasedLP;
  else
  	shares = (increasedLP.mul(totalSupply())).div(beforeLP);

  if(remainingToken > 0)
  	IERC20(tokenB).transfer(_msgSender(), remainingToken);
  if(remainingKlay > 0)
  	msg.sender.transfer(remainingKlay);

  _mint(_msgSender(), shares);
}
```

**Comment**

_mint() 함수 호출을 모든 작업이 완료된 후 수행함으로써 재진입 공격 시 이점을 제거함.

- 공격자에게 불리한 작업(`IERC20(token).TransferFrom`)을 우선적으로 호출한 후 `_mint()`를 호출한다.
-  `payable(address).transfer`로 재진입 공격 시 _mint() 함수가 호출되지 않아 totalSupply()가 증가하지 않는다. 따라서, shares 계산 시 공격자에게 불리한 결과값을 반환한다.



`withdraw()`

```
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
```

**Comment**

_burn() 함수를 최우선적으로 호출함으로써 재진입 공격 시 이점을 제거함.

* 공격자에게 불리한 작업(`_burn()`)을 먼저 수행한다. 이후 `IERC20(token).TransferFrom()` 함수를 호출한다.
* `payable(address).transfer`함수를 `withdraw` 함수의 마지막에서 호출함으로써 재진입 공격을 통한 이점을 제거함. 





### Arithmetic Overflow and Underflow

**방지 기법**

- [SafeMath](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol)를 사용하여 오버플로 및 언더플로우를 방지함.
  - 모든 uint256 타입 데이터 사칙 연산에 SafeMath 함수를 적용함.





### Self Destruct

**방지 기법**

- Trust 컨트랙트에서 selfdestruct를 사용하지 않음.



`_teamReward()`

```java
uint256 estimated = IKSLP(klayKspPool).estimatePos(ksp, reward);
uint256 least = (estimated.mul(99)).div(100);

uint256 beforeKlay = (payable(address(this))).balance;
address[] memory path = new address[](0);
IKSP(ksp).exchangeKctPos(ksp, reward, address(0), least, path);
uint256 afterKlay = (payable(address(this))).balance;

uint256 amount = afterKlay.sub(beforeKlay);
owner.transfer(amount);

return reward;
```

- 특정 KLAY 잔고값(address(this).balance)에 의한 시스템 의사 결정 부분이 존재하지 않음.





### Accessing Private Data

**방지 기법**

- Trust 컨트랙트에 민감한 정보를 저장하지 않음.





### Delegatecall

**방지 기법**

- Trust 컨트랙트에서 delegatecall을 사용하지 않음.





### Source of Randomness

**방지 기법**

- blockhash 및 block.timestamp을 통해 무작위성을 요구하는 부분이 존재하지 않음





### Denial of Service

**방지 기법**

- 지정된 컨트랙트 및 Owner 외의 Address에 KLAY를 전송하는 코드가 존재하지 않음 
  - 잠재적 위험성: Ownership 탈취 시 swap() 호출을 사용할 수 없게 만들 수 있음. 
    - 예치된 기초 자산을 출금(withdraw)하는 부분에 영향을 주지 않음.
    - 피해 범위는 최종 재예치 이후부터 보상으로 받는 KSP에 한정됨.
    - 탈취 시 대응 방안: F/E 레벨에서 입금 버튼 비활성화 및 공지





### Phishing with tx.origin

**방지 기법**

- Trust 컨트랙트에서 tx.origin을 사용하지 않음.





### Hiding Malicious Code with External Contract

Solidity는 address에 지정된 컨트랙트가 형변환(Casting)되지 않은 경우에도 함수를 호출할 수 있다. 이 취약성을 이용하여 악성 코드를 숨길 수 있다.

**방지 기법**

- 외부 컨트랙트를 검사할 수 있도록 외부 컨트랙트의 주소를 공개함.

  ```java
  address public tokenA;
  address public tokenB;
  
  address public klayKspPool;
  
  address public ksp;
  address public kslp;
  
  uint256 public fee;
  address public teamWallet;
  ```





### Front Running

**방지 기법**

- 공격자가 Front Running을 수행했을 때 얻을 수 있는 이점이 존재하지 않음.





### Block Timestamp Manipulation

**방지 기법**

- Trust 컨트랙트에서 block.timestamp을 사용하지 않음.





### Signature Replay

**방지 기법**

- Trust 컨트랙트에서 Sign messages를 이용하지 않음.





## Owner 주소의 개인키가 탈취될 경우 위험성

Owner의 개인 키(Private Key)가 공격자에 의해 탈취될 경우, onlyOwner 한정자가 적용된 함수들이 악용될 잠재적 위험성을 검토한다.



**onlyOwner 한정자 적용 함수 목록**:

- rebalance() 
- claim()
- swap()
- addLiquidityAll()
- setFee()
- setTeamWallet()



`rebalance()`

```
function rebalance() public virtual override onlyOwner {
  _claim();
  _swap();
  _addLiquidityAll();
}
```

**Comment**

rebalance() 함수는 _claim(), _swap(), _addLiquidityAll() 3가지 함수를 순차적으로 호출함.



`claim()`

```
function claim() public onlyOwner {
	_claim();
}

function _claim() internal {
	IKSLP(kslp).claimReward();
}
```

**Comment**

claim() 함수는 [Klayswap LP](https://docs.klayswap.com/contract/exchange) 컨트랙트의 claimReward() 함수를 호출하여 누적 KSP 보상을 수령함. 고정된 컨트랙트 주소에 지정된 함수만 호출됨으로 악용 가능성이 존재하지 않음. 



`swap()`

```
function swap() public onlyOwner {
	_swap();
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
```

```
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
```

**Comment**

**잠재적 위험성**: **swap() 함수 불능**; transferOwnership()으로 owner 주소를 receive 함수가 구현되지 않은 컨트랙트 주소로 변경 시 swap() 함수가 수행될 수 없음. 따라서 보상으로 받는 KSP를 재예치할 수 없음. 그러나, 예치된 자산 출금(withdraw)에 영향을 주지는 않음.

**결론적으로, 피해 범위는 마지막 재예치 시점 이후부터 보상으로 받는 KSP에 한정됨.**



**대응책**

> 위험 감지: OwnershipTransferred 이벤트 모니터링

> 대응: 
>
> * F/E에서 입금 버튼 비활성화를 통한 추가 입금 방지. 
> * 신속한 공지로 출금 유도를 통해 재예치 불가능 시간 노출을 최소화함.

> 예방: Owner 개인키 암호화를 통해 탈취 가능성을 최소화함.





`addLiquidityAll()`

```
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

function _addLiquidity(uint256 _amountKlay, uint256 _amountToken) internal { 
    IKSLP(kslp).addKlayLiquidity{value: _amountKlay}(_amountToken);
}
```

**Comment**

addLiquidity() 함수는 [Klayswap LP](https://docs.klayswap.com/contract/exchange) 컨트랙트의 addKlayLiquidity() 함수를 호출하여 Trust에 예치된 자산 전체를 Klayswap LP에 예치함. 고정된 컨트랙트 주소에 지정된 함수만 호출됨으로 악용 가능성이 존재하지 않음 





`setFee()`

```
function setFee(uint256 _fee) public onlyOwner {
    require(0 <= _fee && _fee <= 3000, "The fee must be between 0 and 10000");
    require(_fee != fee, "Can't set the same value as before");
    emit FeeChanged(fee, _fee);
    fee = _fee;
}
```

**Comment**

**잠재적 위험성**: **보상 토큰 탈취**; fee의 값을 최대값인 10000(100%)으로 설정할 경우 보상 KSP를 재예치할 수 없음. 그러나, 예치된 자산 출금(withdraw)에 영향을 주지는 않음.

**결론적으로, 피해 범위는 최종 재예치 이후부터 보상으로 받는 KSP에 한정됨.**



**대응책**

> 위험 감지: 
>
> * FeeChanged 이벤트 모니터링. 
> * fee는 public 멤버변수로 누구나 현재 값을 확인할 수 있다. F/E에 fee값 표시.

> 대응: 
>
> - F/E에서 입금 버튼 비활성화를 통한 추가 입금 방지. 
> - 신속한 공지로 출금 유도를 통해 재예치 불가능 시간 노출을 최소화함.

> 예방: Owner 개인키 암호화를 통해 탈취 가능성을 최소화함.





`setTeamWallet()`

```
function setTeamWallet(address _teamWallet) public onlyOwner {
    require(_teamWallet != address(0), "Team wallet address can't be 0x0");
    require(_teamWallet != teamWallet, "Can't set the same value as before");
    emit TeamWalletChanged(teamWallet, _teamWallet);
    teamWallet = _teamWallet;
}
```

teamWallet이 사용되는 코드 부분에 위험성이 존재하지 않음.

```
IERC20(ksp).transfer(teamWallet, reward);
```





### Non-upgradable Smart Contract

Trust 스마트 컨트랙트는 Upgradable Pattern이 적용되어 있지 않으므로 컨트랙트 코드가 임의로 변경될 가능성이 존재하지 않는다. 



> 전문 Audit 업체의 감사를 통해 검증받은 DeFi 프로젝트들에서도 러그 풀(Rug pull)이 발생한 사례가 존재한다. 대부분의 경우, 주요 컨트랙트에 Upgradable Pattern이 적용되어 Ownership에 의한 악의적 컨트랙트 코드 변경이 원인이다. Trust 컨트랙트는 이러한 잠재적 위험성을 사전에 차단하기 위해 Proxy 컨트랙트를 사용하지 않는다.





## 검증 결과

* Ownership에 의한 잠재적 러그 풀(Rug pull) 가능성은 발견하지 못함.
* 12개의 보안 검사 항목 중 11개의 항목이 해당사항 없음. 잠재적 위험성이 발견된 1개의 항목(Denial of Service)의 경우 Owner 개인키 탈취가 전제 조건이며, 예치된 기초 자산에는 영향을 주지 않음. 손실을 최소화 하기 위한 방안으로 신속한 위험 감지와 대응 방안을 마련해 둠.
  * 최대 피해 범위 : 최종 재예치 시점 이후부터 누적된 보상 KSP
  * 대응 방안: 관련 Event 감지에 따른 자동 F/E 수준의 입금차단 및 알림 처리

