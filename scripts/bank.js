

// const contract = require("@truffle/contract");
const assert = require('assert');
const colors = require('colors');
const fs = require('fs');
const { expectEvent, singletons, constants, expectRevert } = require('@openzeppelin/test-helpers');
const HDWalletProvider = require('@truffle/hdwallet-provider');
const privateKey = fs.readFileSync(__dirname + '/../.secret', 'utf-8');

const Web3 = require('web3');

const provider = new HDWalletProvider(privateKey, `https://data-seed-prebsc-1-s1.binance.org:8545`);
const web3 = new Web3(provider);
const Contract = web3.eth.Contract;
const BN = web3.utils.BN;

function getContractAt(name, addr) {
  var jsonInterface = require("../build/contracts/"+ name +".json");
  // console.log(jsonInterface)
  return new Contract(jsonInterface.abi, addr);
}

function wait(ms) {
  return new Promise((resolve, reject) => {
    setTimeout(resolve, ms);
  })
}

const address = require('../address.json');
let minABI = require('./erc20.json');

async function main(
  testAdaptors = [], 
  baseToken = '0xDfb1211E2694193df5765d54350e1145FD2404A1', 
  targetRouter = null, 
  testAmount =  1 * 1e16
) {

  // const baseToken = '0xDfb1211E2694193df5765d54350e1145FD2404A1';
  const accounts = await web3.eth.getAccounts();
  const nonOwner = accounts[0];
  const founder = accounts[0];
  // const testAmount = 1 * 1e16;

  let BASE = 1e18;
  let testAll = testAdaptors.length > 1;
  let currentAdaporType = testAll ? testAdaptors[0] : testAdaptors[0];
  let baseTk = new web3.eth.Contract(minABI, baseToken);
  let saverBalance = (await baseTk.methods.balanceOf(address.Saver).call()) / BASE;

  console.log("founder status".green);
  let fStatus = {
    saverBalance: saverBalance,
    balance: (await web3.eth.getBalance(founder)) / BASE,
    baseTokenBalance: (await baseTk.methods.balanceOf(founder).call()) / BASE
  }
  console.table([fStatus], Object.keys(fStatus));

  let bank = await getContractAt('Bank', address.Bank);

  const result = await bank.methods.deposit(baseToken, `${testAmount}`).send({
    from: founder
  });

  console.log('deposit', 'on', result.transactionHash)
  console.log('wait 5 second then withdraw');
  await wait(5 * 1000);

  const balance = await bank.methods.getUserBalance(founder, baseToken);
  console.log('balance', balance);

  const wresult = await bank.methods.withdraw(baseToken, `${testAmount}`).send({
    from: accounts[0]
  });

  console.log('withdraw', 'on', wresult.transactionHash)

 
  console.log("after founder status")
  let flStatus = {
    balance: (await web3.eth.getBalance(founder)) / BASE,
    baseTokenBalance: (await baseTk.methods.balanceOf(founder).call()) / BASE
  }
  console.table([
    flStatus
  ], Object.keys(flStatus)
  );

  process.exit();
}

main(['AlpacaAdaptor'])
  .catch(err => console.log(err));