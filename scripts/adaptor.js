

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
  let holdBalance = await baseTk.methods.balanceOf(founder).call();
  if (holdBalance < testAmount && saverBalance < 0) {
    console.error('founder not enought', holdBalance / BASE)
    process.exit();
  }

  if (saverBalance <= 0)  {
    console.log("send", testAmount / BASE, 'to Saver');
    const sendResult = await baseTk.methods.
      transfer(
        address.Saver, 
        ''+testAmount
      )
      .send({
        from: founder
      });

    if (sendResult) {
      console.log("tokend sended");
    }
  }

  let saver = await getContractAt('Saver', address.Saver);
  let allAdaptors = testAdaptors.map(_ => ({name:_, addr: address[_] }));

  // let adaptor = await getContractAt(currentAdaporType, address[currentAdaporType]);
  let AdaptorRouter = await getContractAt('AdaptorRouter', address.AdaptorRouter);
  
  if (targetRouter && !testAll) {
    // add Pair befor
    await AdaptorRouter.methods.addPair(
      baseToken, 
      currentAdaporType, 
      targetRouter
    ).send({
      from: accounts[0]
    });
  }

  await saver.methods.setAdaptors(
    allAdaptors.map(_ => _.addr)
  ).send({
    from: accounts[0]
  });

  console.log('adaptor seted');
  await wait(5 * 1000);;
  console.log((await saver.methods.getAPRs(baseToken).call()));
  // console.log('adapator status');
  // const statusData = {
  //   valutAddr: await AdaptorRouter.methods.getPair(baseToken, currentAdaporType).call(),
  //   priceInToken: (await adaptor.methods.getPriceInToken(baseToken).call()) / BASE,
  //   amount: (await adaptor.methods.getAmount(baseToken).call()) / BASE,
  //   rate: (await adaptor.methods.getRate(baseToken).call())
  // }
  // console.table([statusData], Object.keys(statusData))
  console.log('saver status');
  console.table([
    [
     {
      balance: (await baseTk.methods.balanceOf(address.Saver).call()) / BASE,
      amount: (await saver.methods.getAmount(baseToken).call()) / BASE,
      rate: (await saver.methods.getRate(baseToken).call()),
      aprs: (await saver.methods.getAPRs(baseToken).call()).aprs,
     }
    ]
  ], [
    'balance',
    'amount',
    'rate',
    'aprs'
  ])

  console.log('do rebalance');
  await wait(5 * 1000);
  const result = await saver.methods
    .rebalance(baseToken)
    .send({
      from: accounts[0]
    });
  
  console.log('rebalance', 'on', result.transactionHash)
  console.log('wait 5 second then withdraw');
  await wait(5 * 1000);;

  // const nowUsedAdaptor = await saver.methods.getCurrentAdaptorsUsed(baseToken, [0]).call();
  // let userAdpator = allAdaptors.filter(_ => _.addr == nowUsedAdaptor);
  // console.log(nowUsedAdaptor, userAdpator);
  // let adaptor = await getContractAt(userAdpator[0].name, nowUsedAdaptor);
  const adaptorAmounNow = await saver.methods.getAmount(baseToken).call();
  // const adaptorPriceNow = await adaptor.methods.getPriceInToken(baseToken).call();
  // try withdraw
  if (adaptorAmounNow > 0) {
    // console.table([
    //   {
    //     adaptorAmounNow: adaptorAmounNow/BASE,
    //     adaptorPriceNow: adaptorPriceNow/BASE
    //   }
    // ], [
    //   'adaptorAmounNow',
    //   'adaptorPriceNow'
    // ])
    try {
      const withdrawResult = await saver.methods.
        withdraw(baseToken, adaptorAmounNow, founder)
        .send({
          from: accounts[0]
        });
      console.log('withdraw', 'on', withdrawResult.transactionHash)
    } catch (e) {
      console.log("withdrawResult.error", e.toString());
    }
  } else {
    console.error('after reblance adaptorAmount is zero')
  }

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

module.exports = {
  main
}