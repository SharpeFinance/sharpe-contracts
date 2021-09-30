
const { expectEvent, singletons, constants, BN, expectRevert } = require('@openzeppelin/test-helpers');

const VenusAdaptor = artifacts.require('VenusAdaptor');
const cDAIMock = artifacts.require('cDAIMock');
const WhitePaperMock = artifacts.require('WhitePaperMock');

const AlpacaAdaptor = artifacts.require('AlpacaAdaptor');
const AdaptorRouter = artifacts.require("AdaptorRouter");
const iDAIMock = artifacts.require('iDAIMock');
const TripleSlopeModel = artifacts.require('TripleSlopeModel');
const iDAIConfigMock = artifacts.require('iDAIConfigMock');
const DAIMock = artifacts.require('DAIMock');
const Saver = artifacts.require('Saver');

const Bank = artifacts.require('Bank');
const Registry = artifacts.require('Registry');
const BasicModel = artifacts.require('BasicModel');

const BNify = n => new BN(String(n));

contract('Bank', function ([_, creator, nonOwner, someone, foo]) {
  beforeEach(async function() {

    this.one = new BN('1000000000000000000');
    this.oneCToken = new BN('100000000'); // 8 decimals

    this.DAIMock = await DAIMock.new({from: creator});
    this.adaptorRouter = await AdaptorRouter.new({ from: creator})
    this.saver = await Saver.new({ from: creator });

    this.TripleSlopeModel = await TripleSlopeModel.new({from: creator});
    this.iDAIConfigMock = await iDAIConfigMock.new(
      this.TripleSlopeModel.address,
      { from: creator }
    );
    this.iDAIMock = await iDAIMock.new(
      this.DAIMock.address, 
      creator, 
      this.iDAIConfigMock.address, 
      {from: creator}
    );

    this.alpacaAdaptor = await AlpacaAdaptor.new(
      this.adaptorRouter.address, 
      this.saver.address,
      { from: creator }
    )

    // venus 
    this.WhitePaperMock = await WhitePaperMock.new({from: creator});
    this.cDAIMock = await cDAIMock.new(
      this.DAIMock.address, 
      creator, 
      this.WhitePaperMock.address, 
      {from: creator}
    );

    this.venusAdaptor = await VenusAdaptor.new(
      this.adaptorRouter.address, 
      this.saver.address,
      { from: creator }
    )


    this.registry = await Registry.new();
    this.model = await BasicModel.new();
    this.bank = await Bank.new(this.registry.address);

    await this.adaptorRouter.addPair(
      this.DAIMock.address, 
      'AlpacaAdaptor',
      this.iDAIMock.address, 
      { from: creator }
    );

    await this.adaptorRouter.addPair(
      this.DAIMock.address, 
      'VenusAdaptor',
      this.cDAIMock.address, 
      { from: creator }
    );

    await this.saver.setAdaptors(
      [
        this.alpacaAdaptor.address, 
        this.venusAdaptor.address
      ], 
      { from: creator }
    );

    await this.registry.setSaver(this.saver.address);
    await this.registry.setInterestModel(this.model.address);
  })


  it('deposit', async function () {
    await this.DAIMock.transfer(this.iDAIMock.address, BNify('100').mul(this.one), {from: creator});
    await this.iDAIMock.setVaultDebtVal(BNify('50').mul(this.one));

    await this.DAIMock.transfer(
      someone, 
      BNify('1000').mul(this.one), 
      {from: creator}
    );

    await this.DAIMock.approve(this.bank.address, BNify('100000').mul(this.one), {
      from: someone
    });

    const interestRate = await this.bank.getInterestRate(
      this.DAIMock.address, 
      10,
      20
    );

    // await this.bank.initPool(this.DAIMock.address);
    console.log('interestRate', interestRate.toString())
    await this.bank.deposit(
      this.DAIMock.address,
      BNify('100').mul(this.one), 
      {
      from: someone
    });

    const self = this;
    async function dumpInfo() {
      const info = await self.bank.poolMap(self.DAIMock.address);
      const userInfo = await self.bank.userMap(someone, self.DAIMock.address);
      const newInfo = {};
      for (var key in info) {
        newInfo[key] = info[key].toString();
      }

      console.log({
        poolInfo: newInfo,
        userInfo: Object.keys(userInfo).reduce((all, key) =>  {
          all[key] = userInfo[key].toString();
          return all
        }, {})
      });
    }

    await dumpInfo();

    // await this.bank.deposit(
    //   this.DAIMock.address,
    //   BNify('100').mul(this.one), 
    //   {
    //   from: someone
    // });

    // await dumpInfo();

    // await this.bank.deposit(
    //   this.DAIMock.address,
    //   BNify('100').mul(this.one), 
    //   {
    //   from: someone
    // });

    // await dumpInfo();

    // check balance
    const leftBalance = await this.DAIMock.balanceOf(someone)
    leftBalance.should.be.bignumber.equal(BNify('0'), 'nothing left');

    // // check getAmount
    // const amount = await this.saver.getAmount(this.DAIMock.address);
    // amount.should.be.bignumber.equal(BNify('100').mul(this.one), 'getAmount match');

    // const usedAdaptor = await this.saver.getCurrentAdaptorsUsed(this.DAIMock.address, [0]);
    
    // console.log(
    //   usedAdaptor.toString(), 
    //   this.alpacaAdaptor.address.toString()
    // )

    // usedAdaptor.should.be.equal(usedAdaptor.toString(), this.venusAdaptor.address.toString(),
    //  'adaptor venus');
    // const targetMock = usedAdaptor.toString() == this.venusAdaptor.address.toString() ? this.cDAIMock  : this.iDAIMock

    // const venusBalance = await targetMock.balanceOf(targetMock.address)
    //  venusBalance.should.be.bignumber.equal(BNify('100').mul(this.one), 
    //  'venus hold all balance')

    //  const adaptorCtokenBalances = await targetMock.balanceOf(usedAdaptor)
    //  adaptorCtokenBalances.should.be.bignumber.equal(BNify('500000000000'), 
    //  'adaptor hold all cToken balance')
  });


  // it('withdraw', async function () {
  //   await this.DAIMock.transfer(this.iDAIMock.address, BNify('100').mul(this.one), {from: creator});
  //   await this.iDAIMock.setVaultDebtVal(BNify('50').mul(this.one));

  //   await this.DAIMock.transfer(
  //     this.saver.address, 
  //     BNify('100').mul(this.one), 
  //     {from: creator}
  //   );

  //    // fund cDAIMock with 100 DAI
  //    await this.DAIMock.transfer(
  //     this.cDAIMock.address,
  //     BNify('100').mul(this.one), 
  //     {from: creator}
  //   );

  //   await this.saver.rebalance(
  //     this.DAIMock.address, 
  //     {
  //     from: creator
  //   });

  //   const allAmount = await this.saver.getAmount(this.DAIMock.address);
  //   console.log('saver amount', allAmount.div(this.one).toString());

  //   await this.saver.withdraw(this.DAIMock.address, BNify('100').mul(this.one), nonOwner);
  //   // console.log((await this.DAIMock.balanceOf(nonOwner)).div(this.one).toString());
  //   (await this.DAIMock.balanceOf(nonOwner)).div(this.one).toString().should.be.equal("100");
  //   //  const afterOneWithdrawAmount = await this.saver.getAmount(this.DAIMock.address);
  //   //  console.log(afterOneWithdrawAmount.div(this.one).toString());

  //   //  const afterWithdrawBalance = await this.DAIMock.balanceOf(nonOwner)
  //   //  afterWithdrawBalance.should.be.bignumber.equal(BNify('0'), 'all withdraw left');
  // });

})