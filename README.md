# Bluewhale Trust

Bluewhale Trust Pool은 KLAYswap 유동성 풀 재예치 투자자의 반복적인 작업을 자동화하는 스마트 컨트랙트입니다.



## 컨트랙트 보안성 보고서(Smart Contract Security Report)

* [KctTrust](./report/KctTrust/README.md)
* [KlayTrust](./report/KlayTrust/README.md)



## Build

**모듈 설치**

```
npm install
```

설치 모듈 :

* openzeppelin-solidity
* @truffle/hdwallet-provider



모듈 변경 사항: 

node_modules/openzeppelin-solidity/contract/token/ERC20/ERC20.sol

```
constructor (string memory name_, string memory symbol_, uint8 decimals_) public {
    _name = name_;
    _symbol = symbol_;
    _decimals = decimals_;
}
```

