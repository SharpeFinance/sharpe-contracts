const AlpacaAdaptor = artifacts.require("AlpacaAdaptor");
const AdaptorRouter = artifacts.require("AdaptorRouter");
const VenusAdaptor = artifacts.require("VenusAdaptor");
const Registry = artifacts.require("Registry");
const BasicModel = artifacts.require("BasicModel");

const Bank = artifacts.require("Bank");
const Vault = artifacts.require("Vault");
const Saver = artifacts.require("Saver");

const fs = require('fs');

module.exports = async function (deployer, network, accounts) {
  // console.log(accounts, network)
  await Promise.all([
    await deployer.deploy(AdaptorRouter),
    await deployer.deploy(Saver),
    await deployer.deploy(Registry),
    await deployer.deploy(BasicModel)
  ]);

  const [
    routerInstance,
    saver,
    registry,
    basicModel
  ] = await Promise.all([
    await AdaptorRouter.deployed(),
    await Saver.deployed(),
    await Registry.deployed(),
    await BasicModel.deployed(),
  ]);

  const routerAddr = routerInstance.address;
  const saverAddr = saver.address;
  
  await Promise.all([
    await deployer.deploy(AlpacaAdaptor, routerAddr, saverAddr),
    await deployer.deploy(VenusAdaptor, routerAddr, saverAddr),
    await deployer.deploy(Bank, registry.address),
    await deployer.deploy(Vault, registry.address),
  ]);

  await registry.setSaver(saverAddr);
  await registry.setInterestModel(basicModel.address);

  const [ alpaca, venus, bank, vault ] = await Promise.all([
    await AlpacaAdaptor.deployed(),
    await VenusAdaptor.deployed(),
    await Bank.deployed(),
    await Vault.deployed()
  ]);

  const restult = await saver.setAdaptors([
    alpaca.address,
    venus.address
  ]);

  let WNativeToken = '0xDfb1211E2694193df5765d54350e1145FD2404A1';
  let pairInfos = [];
  if (network == 'testnet') {
    pairInfos = [
      {
        baseToken: '0xDfb1211E2694193df5765d54350e1145FD2404A1',
        adaptor: 'AlpacaAdaptor',
        target: '0xf9d32C5E10Dd51511894b360e6bD39D7573450F9'
      },
      {
        baseToken: '0xDfb1211E2694193df5765d54350e1145FD2404A1',
        adaptor: 'VenusAdaptor',
        target: '0x2E7222e51c0f6e98610A1543Aa3836E092CDe62c'
      },
    ]
  }
  const createPairs = await Promise.all(pairInfos.map(pairInfo => routerInstance.addPair(
    pairInfo.baseToken, 
    pairInfo.adaptor, 
    pairInfo.target
  )));

  await routerInstance.setWrappedNativeAddr(WNativeToken);
  
  fs.writeFileSync('./address.json', JSON.stringify({
    AdaptorRouter: routerInstance.address,
    Saver: saverAddr,
    AlpacaAdaptor: alpaca.address,
    VenusAdaptor: venus.address,
    Registry: registry.address,
    Bank: bank.address,
    Vault: vault.address
  }))
  // console.log(createPairs)
};
