# Deployments

Record of Router deployments address.

## Pepper Router Contract

### Mainnet

#### 2024-08-22

  Router Contract: 0x6dFCA04DDA768A0F940778c51e2B5c319b471c93

#### 2024-09-12

  Router Contract: 0x085b698cd2FA7C7EF0cCe95493B52Fd4566DdA99

#### 2024-09-16

  Router Contract: 0xaA22d625fE43b354D3B41Ee4e8A942F1aC76794D

#### 2024-09-16

  Router Contract: 0xA24d75601C9b69a604A4669509CFaeeF68a1dd5B

# Verify contracts

```bash
forge verify-contract 0xA24d75601C9b69a604A4669509CFaeeF68a1dd5B ./contracts/PepperRouteProcessor.sol:PepperRouteProcessor \
--constructor-args $(cast abi-encode "constructor(address,address[])" 0xa90EA397380DA7f790E4062f5BF4aF470b9099AC '[0xA1D2fc16b435F91295420D40d6a98bB1302080D9, 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722]') \
--watch
```
