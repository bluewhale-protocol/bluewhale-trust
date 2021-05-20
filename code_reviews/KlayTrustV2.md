# KlayTrust(V2) Code Review

본 문서는 KlayTrust(V2) 스마트 컨트랙트에 대한 코드 리뷰를 목적으로 작성되었습니다.

<br /><br />

## 문서 개정 이력

| 개정 번호    | 개정 일자  | 구분      | 개정 내용           |
| ------------ | ---------- | --------- | ------------------- |
| CR-KLTRU-001 | 2021-05-19 | 신규 작성 | 초안 작성           |
| CR-KLTRU-002 | 2021-05-20 | 내용 추가 | withdrawKSLP() 추가 |

<br /><br />

## 리뷰 파일

* [KlayTrustV2.sol](../contracts/KlayTrustV2.sol)

<br /><br />

## 상속

```
contract KlayTrustV2 is BaseTrust
```

KlayTrustV2는 [BaseTrust.sol](../contracts/BaseTrust.sol)의 BaseTrust 컨트랙트를 상속한다.

<br /><br />

## 함수 목록

* **생성자**
  *  constructor(string memory _name, string memory _symbol, address _ksp, address _kslp) public
* **읽기 전용(view)**
  * 없음
* **상태 수정 가능**
  * function deposit(uint256 amountA, uint256 amountB) external
  * function depositKlay(uint256 _amount) external payable
  * function withdraw(uint256 _shares) external
  * function withdrawKSLP(uint256 _shares) external 

<br /><br />

## 생성자

**매개변수**

- `_name` : Trust의 ERC20 규격 토큰 이름
- `_symbol` : Trust의 ERC20 규격 토큰 심볼
- `_ksp` :  KSP 토큰 컨트랙트 주소로 Klayswap 유동성 풀 예치 보상 토큰에 해당한다. 또한 Trust에서 보상 토큰을 기초자산으로 환전하는 스왑 프로토콜의 주소이다.
- `_kslp` : Klayswap 유동성 풀 컨트랙트 주소로 Trust가 투자하는 대상이 된다.

<br />

```
constructor(
  string memory _name,
  string memory _symbol,
  address _ksp,
  address _kslp
) public BaseTrust(_name, _symbol, _ksp, _kslp) { }
```

`(BaseTrust)constructor`

```
constructor(
  string memory _name,
  string memory _symbol,
  address _ksp,
  address _kslp
) public ERC20(_name, _symbol, ERC20(_kslp).decimals()) {
	...
}
```



생성자의 각 매개변수는 부모 컨트랙트 BaseTrust로 전달되어 각각 상태변수로 기록된다.

<br /><br />

## 상태 수정 가능 함수

### deposit

KlayTrustV2에서는 deposit() 함수를 사용하지 않는다.

```
function deposit(uint256 amountA, uint256 amountB) external virtual override {
	revert();
}
```

<br />

### depositKlay

depositKlay는 사용자가 기초 자산을 Trust에 예치하기 위해 호출하는 함수이다. 사용자는 depositKlay 함수를 통해 기초 자산을 예치하고, 예치 수량에 대응되는 LP 토큰을 발행 받는다.

KlayTrustV2는 Klay-Kct 토큰 쌍을 함께 예치하는 컨트랙트로 함수 호출 시 예치할 Kct 토큰의 양을 입력값으로 전달한다. 또한 함수를 호출할 때 Klay를 컨트랙트에 전달한다. 예치된 자산은 함수 내에서 즉시 Klayswap 유동성 풀에 예치된다. Klayswap 유동성 풀 예치 시 LP 토큰인 KSLP를 받는다. Trust는 Klayswap 유동성 풀로부터 받은 KSLP 수량을 바탕으로 자체 LP 토큰인 BWTP를 함수 호출자에게 발행한다.

<br />

**매개변수**

* `_amount` :  예치할 Kct Token의 수량

**한정자**

* payable : depositKlay 함수는 호출 시 Klay 송금 가능한 함수이다.
* nonReentrant : depositKlay 함수는 재진입이 불가능하다.

<br />

**전체 코드**

```
function depositKlay(
	uint256 _amount
) external payable virtual override nonReentrant {
  require(msg.value > 0 && _amount > 0, "Deposit must be greater than 0");

  (uint256 beforeKlayInKSLP, uint256 beforeTokenInKSLP) = IKSLP(kslp).getCurrentPool();
  uint256 beforeLP = _balanceKSLP();

  IERC20(tokenB).transferFrom(_msgSender(), address(this), _amount);
  _addLiquidity(msg.value, _amount);

  (uint256 afterKlayInKSLP, uint256 afterTokenInKSLP) = IKSLP(kslp).getCurrentPool();
  uint256 afterLP = _balanceKSLP();

  uint256 depositedKlay = afterKlayInKSLP.sub(beforeKlayInKSLP);
  uint256 depositedToken = afterTokenInKSLP.sub(beforeTokenInKSLP);

  uint256 remainingKlay = (msg.value).sub(depositedKlay);
  uint256 remainingToken = _amount.sub(depositedToken);
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

**코드 설명**

* 예치하는 기초자산(Klay, KctToken)의 수량은 각각 0보다 큰 값이어야 한다.

* ```
  require(msg.value > 0 && _amount > 0, "Deposit must be greater than 0");
  ```

* kslp(Klayswap 유동성 풀) 컨트랙트에 입금된 자산을 예치한다. 이 때, Trust에 입금된 자산 중 kslp에 예치 시도 후 남은 잔액을 계산한다.

  * kslp에 자산 예치 전 kslp 내의 두 기초자산의 수량을 기록한다. `IKSLP(kslp).getCurrentPool()`

  * kslp에 자산 예치 전 Trust가 보유한 kslp 수량을 기록한다. `_balanceKSLP()`

  * ```
    function _balanceKSLP() internal view returns (uint256){
    	return IERC20(kslp).balanceOf(address(this));
    }
    ```

  * 함수 호출자로부터 kctToken를 _amount 수량만큼 Trust로 가져온다. (따라서, Approve된 상태여야 한다.)

  * kslp에 기초자산을 예치한다. `_addLiquidity(msg.value, _amount)`

    * Trust의 Klay, Kct 수량은 감소한다.

    * KSLP의 Klay, Kct 수량은 증가한다.

    * Trust의 kslp 수량은 증가한다.

    * Trust가 수령 가능한 ksp가 존재할 경우 자동으로 수령된다. 따라서, Trust의 ksp 수량이 증가할 수 있다.

    * ```
      function _addLiquidity(uint256 _amountA, uint256 _amountB) internal {
      if(tokenA == address(0))
      	IKSLP(kslp).addKlayLiquidity{value: _amountA}(_amountB);
      else
      	IKSLP(kslp).addKctLiquidity(_amountA, _amountB);
      }
      ```

  * kslp에 자산 예치 후 kslp 내의 두 기초자산의 수량을 기록한다. `IKSLP(kslp).getCurrentPool()`

  * kslp에 자산 예치 후 Trust가 보유한 kslp 수량을 기록한다. `_balanceKSLP()`

* ```
  (uint256 beforeKlayInKSLP, uint256 beforeTokenInKSLP) = IKSLP(kslp).getCurrentPool();
  uint256 beforeLP = _balanceKSLP();
  
  IERC20(tokenB).transferFrom(_msgSender(), address(this), _amount);
  _addLiquidity(msg.value, _amount);
  
  (uint256 afterKlayInKSLP, uint256 afterTokenInKSLP) = IKSLP(kslp).getCurrentPool();
  uint256 afterLP = _balanceKSLP();
  ```

* kslp에 예치 후 남은 자산을 계산한다.

  * 남은 Klay 수량 = Trust에 입금된 Klay 수량 - kslp에 예치된 Klay 수량
    * 예치된 Klay 수량 = 예치 후 kslp 내 klay 수량 - 예치 전 kslp 내 klay 수량
  * 남은 Kct 수량 = Trust에 입금된 Kct 수량 - kslp에 예치된 Kct 수량
    * 예치된 Kct 수량 = 예치 후 kslp 내 Kct 수량 - 예치 전 kslp 내 Kct 수량

  ```
  uint256 depositedKlay = afterKlayInKSLP.sub(beforeKlayInKSLP);
  uint256 depositedToken = afterTokenInKSLP.sub(beforeTokenInKSLP);
  
  uint256 remainingKlay = (msg.value).sub(depositedKlay);
  uint256 remainingToken = _amount.sub(depositedToken);
  ```

*  kslp에 예치 후 증가한 kslp 수량을 계산한다.

  * 증가된 kslp 수량 = 예치 후 Trust가 보유한 kslp 수량 - 예치 전 Trust가 보유한 kslp 수량

* ```
  uint256 increasedLP = afterLP.sub(beforeLP);
  ```

* 호출자에게 신규 발행할 지분 토큰(BWTP) 수량을 계산한다.

  * 신규 발행량`shares` : 전체 발행량`totalSupply()` = 증가한 KSLP`increasedLP` : 전체 보유한 KSLP`beforeLP`
  * 따라서, 신규 발행량 = 전체 발행량 x 증가한 KSLP / 전체 보유한 KSLP

* ```
  uint256 shares = 0;
  if (totalSupply() < 1)
  	shares = increasedLP;
  else
  	shares = (increasedLP.mul(totalSupply())).div(beforeLP);
  ```

* 예치 후 남은 자산을 호출자에게 반환한다.

* ```
  if(remainingToken > 0)
  	IERC20(tokenB).transfer(_msgSender(), remainingToken);
  if(remainingKlay > 0)
  	msg.sender.transfer(remainingKlay);
  ```

* 호출자에게 지분 토큰(BWTP)를 발행한다. 

  ```
  _mint(_msgSender(), shares);
  ```

<br /><br />

### withdraw

withdraw는 사용자가 Trust에 예치한 기초 자산 인출을 위해 호출하는 함수이다. 사용자는 withdraw 함수를 통해 지분 토큰(BWTP)을 입금하고, 입금한 지분 토큰 수량에 대응되는 기초 자산(Klay&Kct)을 반환 받는다.

Trust는 Klayswap 유동성 풀에 BWTP에 대응되는 KSLP를 입금하고, 기초 자산을 출금한다. Trust에 입금된 BWTP는 소각되며, Klayswap 유동성 풀에서 출금한 기초자산은 호출자에게 송금된다.

<br />

**매개변수**

- `_shares` :  인출을 희망하는 지분토큰(BWTP) 수량

**한정자**

- nonReentrant : withdraw 함수는 재진입이 불가능하다.

<br />

**전체 코드**

```
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
```

**코드 설명**

- 입금 지분 토큰(BWTP)의 수량은 0보다 큰 값이어야 한다.

- ```
  require(_shares > 0, "Withdraw must be greater than 0");
  ```

- 입금 지분 토큰의 수량은 호출자가 보유한 전체 지분 토큰 수량보다 작거나 같아야한다.

- ```
  uint256 totalShares = balanceOf(msg.sender);
  require(_shares <= totalShares, "Insufficient balance");
  ```

- 입금된 지분 토큰에 대응되는 KSLP 수량을 계산한다.

  - 지분 토큰 대응 KSLP = Trust 보유 KSLP`totalLP` x (입금 지분 토큰`_shares` / 전체 발행량`totalSupply()`)

- ```
  uint256 totalLP = _balanceKSLP();
  uint256 sharesLP = (totalLP.mul(_shares)).div(totalSupply());
  ```

- 입금된 지분 토큰을 소각한다.

- ```
  _burn(msg.sender, _shares);
  ```

- kslp(Klayswap 유동성 풀) 컨트랙트에서 기초 자산을 출금한다. 이 때, kslp에서 출금된 기초 자산의 수량을 계산한다.

  - kslp에 자산 예치 전 kslp 내의 두 기초 자산의 수량을 기록한다. `IKSLP(kslp).getCurrentPool()`

  - kslp에서 기초 자산을 출금한다. `_removeLiquidity(sharesLP);`

    - Trust의 Klay, Kct 수량은 증가한다.

    - KSLP의 Klay, Kct 수량은 감소한다.

    - Trust의 kslp 수량은 감소한다.

    - Trust가 수령가능한 ksp가 존재할 경우 자동으로 수령된다. 따라서, Trust의 ksp 수량이 증가할 수 있다.

    - ```
      function _removeLiquidity(uint256 _amount) internal {
        uint256 totalLP = _balanceKSLP();
        require(_amount <= totalLP, "Required amount exceed balance");
      
        IKSLP(kslp).removeLiquidity(_amount);
      }
      ```

  - kslp에 자산 예치 후 kslp 내의 두 기초 자산의 수량을 기록한다. `IKSLP(kslp).getCurrentPool()`

- ```
  (uint256 beforeKlayInKSLP, uint256 beforeTokenInKSLP) = IKSLP(kslp).getCurrentPool();
  _removeLiquidity(sharesLP);
  (uint256 afterKlayInKSLP, uint256 afterTokenInKSLP) = IKSLP(kslp).getCurrentPool();
  ```

- kslp에서 출금된 기초 자산을 계산한다.

  - 출금된 Klay 수량 = 출금 전 kslp 내 klay 수량 - 출금 후 kslp 내 klay 수량
  - 출금된 Kct 수량 =  출금 전 kslp 내 Kct 수량 - 출금 후 kslp 내 Kct 수량

  ```
  uint256 amountKlay = beforeKlayInKSLP.sub(afterKlayInKSLP);
  uint256 amountToken = beforeTokenInKSLP.sub(afterTokenInKSLP);
  ```

- kslp에서 출금된 기초 자산을 호출자에게 송금한다.

  ``` 
  IERC20(tokenB).transfer(_msgSender(), amountToken);
  msg.sender.transfer(amountKlay);
  ```

<br /><br />

### withdrawKSLP

withdrawKSLP는 Trust가 보유한 KSLP를 직접 인출하기 위해 사용하는 함수이다. 일반적인 경우에는 사용하지 않는다. Klayswap 유동성 풀에서 유동성 제거가 정상적으로 되지 않는 경우를 대비해 준비된 함수이다.

Trust에 입금된 BWTP는 소각되며, 입금 BWTP에 대응되는 KSLP를 호출자에게 송금한다.

<br />

**매개변수**

- `_shares` :  인출을 희망하는 지분토큰(BWTP) 수량

**한정자**

- nonReentrant : withdraw 함수는 재진입이 불가능하다.

<br />

**전체 코드**

```
function withdrawKSLP(uint256 _shares) external nonReentrant {
  require(_shares > 0, "Withdraw must be greater than 0");
  require(_shares <= balanceOf(msg.sender), "Insufficient balance");

  uint256 totalLP = _balanceKSLP();
  uint256 sharesLP = (totalLP.mul(_shares)).div(totalSupply());

  _burn(msg.sender, _shares);

  IERC20(kslp).transfer(_msgSender(), sharesLP);
}
```

**코드 설명**

- 입금 지분 토큰(BWTP)의 수량은 0보다 큰 값이어야 한다.

- ```
  require(_shares > 0, "Withdraw must be greater than 0");
  ```

- 입금 지분 토큰의 수량은 호출자가 보유한 전체 지분 토큰 수량보다 작거나 같아야한다.

- ```
  require(_shares <= balanceOf(msg.sender), "Insufficient balance");
  ```

- 입금된 지분 토큰에 대응되는 KSLP 수량을 계산한다.

  - 지분 토큰 대응 KSLP = Trust 보유 KSLP`totalLP` x (입금 지분 토큰`_shares` / 전체 발행량`totalSupply()`)

- ```
  uint256 totalLP = _balanceKSLP();
  uint256 sharesLP = (totalLP.mul(_shares)).div(totalSupply());
  ```

- 입금된 지분 토큰을 소각한다.

- ```
  _burn(msg.sender, _shares);
  ```

- kslp를 호출자에게 송금한다.

  ```
  IERC20(kslp).transfer(_msgSender(), sharesLP);
  ```

<br /><br />