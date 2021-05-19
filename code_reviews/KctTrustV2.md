# KctTrust(V2) Code Review

본 문서는 KctTrust(V2) 스마트 컨트랙트에 대한 코드 리뷰를 목적으로 작성되었습니다.

<br /><br />

## 문서 개정 이력

| 개정 번호    | 개정 일자  | 구분      | 개정 내용 |
| ------------ | ---------- | --------- | --------- |
| CR-KCTRU-001 | 2021-05-19 | 신규 작성 | 초안 작성 |

<br /><br />

## 리뷰 파일

* [KctTrustV2.sol](../contracts/KctTrustV2.sol)

<br /><br />

## 상속

```
contract KctTrustV2 is BaseTrust
```

KctTrustV2는 [BaseTrust.sol](../contracts/BaseTrust.sol)의 BaseTrust 컨트랙트를 상속한다.

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

### depositKlay

KctTrustV2에서는 depositKlay() 함수를 사용하지 않는다.

```
function depositKlay(uint256 amount) external payable virtual override {
	revert();
}
```

<br />

### deposit

deposit은 사용자가 기초 자산을 Trust에 예치하기 위해 호출하는 함수이다. 사용자는 deposit 함수를 통해 기초 자산을 예치하고, 예치 수량에 대응되는 LP 토큰을 발행 받는다.

KctTrustV2는 Kct-Kct 토큰 쌍을 함께 예치하는 컨트랙트로 함수 호출 시 예치할 각 Kct 토큰의 양을 입력값으로 전달한다. 예치된 자산은 함수 내에서 즉시 Klayswap 유동성 풀에 예치된다. Klayswap 유동성 풀 예치 시 LP 토큰인 KSLP를 받는다. Trust는 Klayswap 유동성 풀로부터 받은 KSLP 수량을 바탕으로 자체 LP 토큰인 BWTP를 함수 호출자에게 발행한다.

<br />

**매개변수**

* `_amountA` : 예치할 Kct TokenA의 수량
* `_amountB` : 예치할 Kct TokenB의 수량

**한정자**

* nonReentrant : depositKlay 함수는 재진입이 불가능하다.

<br />

**전체 코드**

```
function deposit(
	uint256 _amountA, 
	uint256 _amountB
) external virtual override nonReentrant {
  require(_amountA > 0 && _amountB > 0, "Deposit must be greater than 0");

  (uint256 beforeAInKSLP, uint256 beforeBInKSLP) = IKSLP(kslp).getCurrentPool();
  uint256 beforeLP = _balanceKSLP();

  IERC20(tokenA).transferFrom(_msgSender(), address(this), _amountA);
  IERC20(tokenB).transferFrom(_msgSender(), address(this), _amountB);
  _addLiquidity(_amountA, _amountB);

  (uint256 afterAInKSLP, uint256 afterBInKSLP) = IKSLP(kslp).getCurrentPool();
  uint256 afterLP = _balanceKSLP();

  uint256 depositedA = afterAInKSLP.sub(beforeAInKSLP);
  uint256 depositedB = afterBInKSLP.sub(beforeBInKSLP);

  uint256 remainingA = _amountA.sub(depositedA);
  uint256 remainingB = _amountB.sub(depositedB);
  uint256 increasedLP = afterLP.sub(beforeLP);

  uint256 shares = 0;
  if (totalSupply() < 1) 
  	shares = increasedLP;
  else
  	shares = (increasedLP.mul(totalSupply())).div(beforeLP);

  if(remainingA > 0)
  	IERC20(tokenA).transfer(_msgSender(), remainingA);
  if(remainingB > 0)
  	IERC20(tokenB).transfer(_msgSender(), remainingB);

  _mint(_msgSender(), shares);
}
```

**코드 설명**

* 예치하는 기초자산(tokenA, tokenB)의 수량은 각각 0보다 큰 값이어야 한다.

* ```
  require(_amountA > 0 && _amountB > 0, "Deposit must be greater than 0");
  ```

* kslp(Klayswap 유동성 풀) 컨트랙트에 입금된 자산을 예치한다. 이 때, Trust에 입금된 자산 중 kslp에 예치 시도 후 남은 잔액을 계산한다.

  * kslp에 자산 예치 전 kslp 내의 두 기초자산의 수량을 기록한다. `IKSLP(kslp).getCurrentPool()`

  * kslp에 자산 예치 전 Trust가 보유한 kslp 수량을 기록한다. `_balanceKSLP()`

  * ```
    function _balanceKSLP() internal view returns (uint256){
    	return IERC20(kslp).balanceOf(address(this));
    }
    ```

  * 함수 호출자로부터 두 kct Token을 _amount 수량만큼 Trust로 가져온다. (따라서, Approve된 상태여야 한다.)

  * kslp에 기초자산을 예치한다. `_addLiquidity(msg.value, _amount)`

    * Trust의 tokenA, tokenB 수량은 감소한다.

    * KSLP의 tokenA, tokenB 수량은 증가한다.

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
  (uint256 beforeAInKSLP, uint256 beforeBInKSLP) = IKSLP(kslp).getCurrentPool();
  uint256 beforeLP = _balanceKSLP();
  
  IERC20(tokenA).transferFrom(_msgSender(), address(this), _amountA);
  IERC20(tokenB).transferFrom(_msgSender(), address(this), _amountB);
  _addLiquidity(_amountA, _amountB);
  
  (uint256 afterAInKSLP, uint256 afterBInKSLP) = IKSLP(kslp).getCurrentPool();
  uint256 afterLP = _balanceKSLP();
```
  
* kslp에 예치 후 남은 자산을 계산한다.

  * 남은 tokenA 수량 = Trust에 입금된 tokenA 수량 - kslp에 예치된 tokenA 수량
    * 예치된 Klay 수량 = 예치 후 kslp 내 tokenA 수량 - 예치 전 kslp 내 tokenA 수량
  * 남은 tokenB 수량 = Trust에 입금된 tokenB 수량 - kslp에 예치된 tokenB 수량
    * 예치된 Kct 수량 = 예치 후 kslp 내 tokenB 수량 - 예치 전 kslp 내 tokenB 수량

  ```
  uint256 depositedA = afterAInKSLP.sub(beforeAInKSLP);
  uint256 depositedB = afterBInKSLP.sub(beforeBInKSLP);
  
  uint256 remainingA = _amountA.sub(depositedA);
  uint256 remainingB = _amountB.sub(depositedB);
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
  if(remainingA > 0)
  	IERC20(tokenA).transfer(_msgSender(), remainingA);
  if(remainingB > 0)
  	IERC20(tokenB).transfer(_msgSender(), remainingB);
  ```

* 호출자에게 지분 토큰(BWTP)를 발행한다. 

  ```
  _mint(_msgSender(), shares);
  ```

<br /><br />

### withdraw

withdraw는 사용자가 Trust에 예치한 기초 자산 인출을 위해 호출하는 함수이다. 사용자는 withdraw 함수를 통해 지분 토큰(BWTP)을 입금하고, 입금한 지분 토큰 수량에 대응되는 기초 자산(tokenA&tokenB)을 반환 받는다.

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

- kslp(Klayswap 유동성 풀) 컨트랙트에서 기초 자산을 출금한다. 이 때, kslp에서 출금된 기초 자산의 수량을 계산한다.

  - kslp에 자산 예치 전 kslp 내의 두 기초 자산의 수량을 기록한다. `IKSLP(kslp).getCurrentPool()`

  - kslp에서 기초 자산을 출금한다. `_removeLiquidity(sharesLP);`

    - Trust의 tokenA, tokenB 수량은 증가한다.

    - KSLP의 tokenA, tokenB 수량은 감소한다.

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
  (uint256 beforeAInKSLP, uint256 beforeBInKSLP) = IKSLP(kslp).getCurrentPool();
  _removeLiquidity(sharesLP);
  (uint256 afterAInKSLP, uint256 afterBInKSLP) = IKSLP(kslp).getCurrentPool();
  ```

- kslp에서 출금된 기초 자산을 계산한다.

  - 출금된 tokenA 수량 = 출금 전 kslp 내 tokenA 수량 - 출금 후 kslp 내 tokenA 수량
  - 출금된 tokenB 수량 = 출금 전 kslp 내 tokenB 수량 - 출금 후 kslp 내 tokenB 수량

  ```
  uint256 withdrawalA = beforeAInKSLP.sub(afterAInKSLP);
  uint256 withdrawalB = beforeBInKSLP.sub(afterBInKSLP);
  ```

- kslp에서 출금된 기초 자산을 호출자에게 송금한다.

  ``` 
  IERC20(tokenA).transfer(_msgSender(), withdrawalA);
  IERC20(tokenB).transfer(_msgSender(), withdrawalB);
  ```

<br /><br />

