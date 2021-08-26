

const { expectEvent, singletons, constants, BN, expectRevert } = require('@openzeppelin/test-helpers');

const VenusAdaptor = artifacts.require('VenusAdaptor');
const AdaptorRouter = artifacts.require("AdaptorRouter");
const cDAIMock = artifacts.require('cDAIMock');
const WhitePaperMock = artifacts.require('WhitePaperMock');
const DAIMock = artifacts.require('DAIMock');
const Saver = artifacts.require('Saver');

const BNify = n => new BN(String(n));

contract('VenusAdaptor', function ([_, creator, nonOwner, someone, foo]) {
  beforeEach(async function() {

    this.one = new BN('1000000000000000000');
    this.oneCToken = new BN('100000000'); // 8 decimals

    this.baseToken = '0xDfb1211E2694193df5765d54350e1145FD2404A1';

    this.DAIMock = await DAIMock.new({from: creator});
    this.saver = await Saver.new({ from: creator });
    
    this.WhitePaperMock = await WhitePaperMock.new({from: creator});
    this.cDAIMock = await cDAIMock.new(
      this.DAIMock.address, 
      creator, 
      this.WhitePaperMock.address, 
      {from: creator}
    );

    this.adaptorRouter = await AdaptorRouter.new({ from: creator})
    this.venusAdaptor = await VenusAdaptor.new(
      this.adaptorRouter.address, 
      this.saver.address,
      { from: creator }
    )

    await this.adaptorRouter.addPair(
      this.DAIMock.address, 
      'VenusAdaptor',
      this.cDAIMock.address, 
      { from: creator }
    );
  })

  it('constructor set a token address', async function () {
    (await this.venusAdaptor.router()).should.equal(this.adaptorRouter.address);
  });

  it('constructor set an underlying address', async function () {
    (await this.venusAdaptor.saver()).should.equal(this.saver.address);
  });

  it('getPriceInToken returns cToken price', async function () {
    const res = await this.venusAdaptor.getPriceInToken.call(this.DAIMock.address, { from: nonOwner });
    const expectedRes = BNify(await this.cDAIMock.exchangeRateStored.call());
    assert.equal(res.toString(), expectedRes.toString(), "should same")
  });

  it('getRate returns current yearly rate (counting fee)', async function () {
    const res = await this.venusAdaptor.getRate.call(
      this.DAIMock.address, 
      { from: nonOwner }
    );
    const rate = await this.cDAIMock.supplyRatePerBlock.call();
    const blocksPerYear = 10512000;
    const expectedRes = BNify(rate).div(BNify(3));
    res.should.not.be.bignumber.equal(BNify('0'));
    res.should.be.bignumber.equal(expectedRes);
  });

  it('deposit returns 0 if no tokens are presenti in this contract', async function () {
    const res = await this.venusAdaptor.deposit.call(this.DAIMock.address, { from: nonOwner });
    assert.equal(res.toString(), BNify('0').toString(), "should same")
  });

  it('deposit creates cTokens and it sends them to msg.sender', async function () {
    // deposit 100 DAI in cDAIWrapper
    await this.DAIMock.transfer(this.venusAdaptor.address, BNify('100').mul(this.one), {from: creator});
    // deposit in Compound with 100 DAI
    const callRes = await this.venusAdaptor.deposit.call(this.DAIMock.address, { from: nonOwner });
    assert.equal(callRes.toString(), BNify('500000000000').toString(), "should same")
    // do the effective tx
    await this.venusAdaptor.deposit(this.DAIMock.address, { from: nonOwner });
    const leftBalance = await this.cDAIMock.balanceOf(this.venusAdaptor.address);
    assert.equal((leftBalance).toString(), "500000000000", "balance should same")
  });

  it('withdraw creates cTokens and it sends them to msg.sender', async function () {
    // fund cDAIMock with 100 DAI
    await this.DAIMock.transfer(
      this.cDAIMock.address,
      BNify('100').mul(this.one), 
      {from: creator}
    );

    // deposit 5000 cDAI in cDAIWrapper
    await this.cDAIMock.transfer(
      this.venusAdaptor.address, 
      BNify('5000').mul(this.oneCToken), 
      {from: creator}
    );

    // redeem in Compound with 5000 cDAI * 0.02 (price) = 100 DAI
    const callRes = await this.venusAdaptor.withdraw.call(
      this.DAIMock.address, 
      BNify('100').mul(this.one), 
      { from: nonOwner }
    );

    assert.equal(
      callRes.toString(), 
      (BNify('100').mul(this.one)).toString(), 
      "should same"
    );
    // do the effective tx
    await this.venusAdaptor.withdraw(
      this.DAIMock.address, 
      BNify('100').mul(this.one), 
      { from: nonOwner }
    );

    assert.equal(
      (await this.DAIMock.balanceOf(nonOwner)).toString(), 
      (BNify('100').mul(this.one)).toString(), 
      "balance should same"
    );
  });

})