const Trust = artifacts.require('KctTrust');

const poolName = 'Bluewhale Trust Pool';
const poolNameSimplified = 'BWTP';
const strategyName = 'Compound Interest';
const strategySimplified = 'CI';

const deployConfig = {
  ksp: '0xc6a2ad8cc6e4a7e08fc37cc5954be07d499e7654' // Klayswap Protocol (KSP)
};

const KSLP = {
  KUSDT_KDAI: {
    pair: 'KUSDT-KDAI',
    kslp: '0xc320066b25B731A11767834839Fe57f9b2186f84', // Klayswap Liquidity Pool (KSLP) kUSDT-kDAI
    decimals: 6
  }
}

module.exports = function (deployer) {
  const name = `${poolName} ${KSLP.KUSDT_KDAI.pair} ${strategyName}`
  const symbol = `${poolNameSimplified} ${KSLP.KUSDT_KDAI.pair} ${strategySimplified}`
  const decimals = KSLP.KUSDT_KDAI.decimals

  await deployer.deploy(Trust, name, symbol, decimals,
    deployConfig.ksp,
    deployConfig.kslp
  );
};
