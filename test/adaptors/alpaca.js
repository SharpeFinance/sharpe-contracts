
const { expectEvent, singletons, constants, BN, expectRevert } = require('@openzeppelin/test-helpers');

const AlpacaAdaptor = artifacts.require('AlpacaAdaptor');
const AdaptorRouter = artifacts.require("AdaptorRouter");
const iDAIMock = artifacts.require('iDAIMock');
const TripleSlopeModel = artifacts.require('TripleSlopeModel');
const iDAIConfigMock = artifacts.require('iDAIConfigMock');
const DAIMock = artifacts.require('DAIMock');
const Saver = artifacts.require('Saver');
const BNify = n => new BN(String(n));

contract('AlpacaAdaptor', function ([_, creator, nonOwner, someone, foo]) {
  beforeEach(async function() {

    this.one = new BN('1000000000000000000');
    this.oneCToken = new BN('100000000'); // 8 decimals

    // this.baseToken = '0xDfb1211E2694193df5765d54350e1145FD2404A1';
    this.DAIMock = await DAIMock.new({from: creator});
    this.TripleSlopeModel = await TripleSlopeModel.new({from: creator});
    this.saver = await Saver.new({ from: creator });
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

    this.adaptorRouter = await AdaptorRouter.new({ from: creator})
    this.adaptor = await AlpacaAdaptor.new(
      this.adaptorRouter.address, 
      this.saver.address,
      { from: creator }
    )

    await this.adaptorRouter.addPair(
      this.DAIMock.address, 
      'AlpacaAdaptor',
      this.iDAIMock.address, 
      { from: creator }
    );
  })

  it('constructor set a token address', async function () {
    (await this.adaptor.router()).should.equal(this.adaptorRouter.address);
  });

  it('constructor set an underlying address', async function () {
    (await this.adaptor.saver()).should.equal(this.saver.address);
  });

  it('deposit returns 0 if no tokens are presenti in this contract', async function () {
    const res = await this.adaptor.deposit.call(this.DAIMock.address, { from: nonOwner });
    assert.equal(res.toString(), BNify('0').toString(), "should same")
  });

  it('getRate', async function () {
    await this.DAIMock.transfer(this.iDAIMock.address, BNify('100').mul(this.one), {from: creator});
    await this.iDAIMock.setVaultDebtVal(BNify('50').mul(this.one));

    const vaultDebtVal = await this.iDAIMock.vaultDebtVal();
    const tokenAddressBalance = await this.DAIMock.balanceOf(this.iDAIMock.address);
    const interestRate =  (await this.iDAIConfigMock.getInterestRate(vaultDebtVal, tokenAddressBalance))
    // console.log({
    //   vaultDebtVal: vaultDebtVal.toString(),
    //   tokenAddressBalance: tokenAddressBalance.toString(),
    //   interestRate: interestRate.toString(),
    //   reservePoolBps: (await this.iDAIConfigMock.getReservePoolBps()).toString(),
    // });
    interestRate.should.be.bignumber.equal('3523310220', 'interestRate');
    vaultDebtVal.should.be.bignumber.equal(BNify('50000000000000000000'), 'vaultDebtVal');
    tokenAddressBalance.should.be.bignumber.equal(BNify('100000000000000000000'), 'tokenAddressBalance');
    const nowRate = await this.adaptor.getRate.call(
      this.DAIMock.address, 
      { from: nonOwner }
    );
    nowRate.should.be.bignumber.equal(BNify('1174436739'), 'rate now same');
  });


  it('deposit creates cTokens and it sends them to msg.sender', async function () {
    // deposit 100 DAI in cDAIWrapper
    await this.DAIMock.transfer(this.adaptor.address, BNify('100').mul(this.one), {from: creator});
    // deposit in Compound with 100 DAI
    const callRes = await this.adaptor.deposit.call(this.DAIMock.address, { from: nonOwner });
    assert.equal(callRes.toString(), BNify('100000000000000000000').toString(), "should same")
    // do the effective tx
    await this.adaptor.deposit(this.DAIMock.address, { from: nonOwner });
    const leftBalance = await this.iDAIMock.balanceOf(this.adaptor.address);
    assert.equal((leftBalance).toString(), "100000000000000000000", "balance should same")
  });


  it('withdraw creates cTokens and it sends them to msg.sender', async function () {
    
    // fund cDAIMock with 100 DAI
    await this.DAIMock.transfer(
      this.iDAIMock.address,
      BNify('100').mul(this.one), 
      {from: creator}
    );

    await this.iDAIMock.transfer(
      this.adaptor.address, 
      BNify('1').mul(this.one), 
      {from: creator}
    );

    // console.log({
    //   totalToken: (await this.iDAIMock.totalToken()).toString(),
    //   totalSupply: (await this.iDAIMock.totalSupply()).toString(),
    // })

    // const amountHold = await this.adaptor.getAmount(this.DAIMock.address);
    // console.log('amountHold', amountHold.toString());
    // redeem in Compound with 5000 cDAI * 0.02 (price) = 100 DAI
    // const callRes = await this.adaptor.withdraw.call(
    //   this.DAIMock.address, 
    //   BNify('100').mul(this.one),
    //   { from: nonOwner }
    // );
    // assert.equal(
    //   callRes.toString(), 
    //   '454545454545454545', 
    //   "should same"
    // );
    
    // do the effective tx
    await this.adaptor.withdraw(
      this.DAIMock.address, 
      BNify('50').mul(this.one), 
      { from: nonOwner }
    );

    assert.equal(
      (await this.DAIMock.balanceOf(nonOwner)).toString(), 
      BNify('50').mul(this.one).toString(), 
      "balance should same"
    );
  });

})