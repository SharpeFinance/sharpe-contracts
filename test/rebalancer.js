const { expectEvent, singletons, constants, BN, expectRevert } = require('@openzeppelin/test-helpers');

const Rebalancer = artifacts.require('Rebalancer');
const BNify = n => new BN(String(n));

contract('Rebalancer', function ([_, creator, manager, nonOwner, someone, foo, saver]) {
  beforeEach(async function () {
    this.one = new BN('1000000000000000000');
    this.ETHAddr = '0x0000000000000000000000000000000000000000';
    this.addr1 = '0x0000000000000000000000000000000000000001';
    this.addr2 = '0x0000000000000000000000000000000000000002';
    this.addr3 = '0x0000000000000000000000000000000000000003';
    this.addr4 = '0x0000000000000000000000000000000000000004';
    this.addrNew = '0x0000000000000000000000000000000000000005';

    this.Rebalancer = await Rebalancer.new(
      this.addr1,
      this.addr2,
      // this.addr3,
      // this.addr4,
      manager,
      { from: creator }
    );
    await this.Rebalancer.setSaver(saver, { from: creator });
  });

  it('constructor set rebalanceManager addr', async function () {
    (await this.Rebalancer.rebalancerManager()).should.equal(manager);
  });
  it('constructor set default allocations', async function () {
    (await this.Rebalancer.lastAmounts(0)).should.be.bignumber.equal(BNify('100000'));
    (await this.Rebalancer.lastAmounts(1)).should.be.bignumber.equal(BNify('0'));
  });
  it('constructor set default addresses', async function () {
    (await this.Rebalancer.lastAmountsAddresses(0)).should.equal(this.addr1);
    (await this.Rebalancer.lastAmountsAddresses(1)).should.equal(this.addr2);
  });
  it('allows onlyOwner to setRebalancerManager', async function () {
    const val = this.addr1;
    await this.Rebalancer.setRebalancerManager(manager, { from: creator });
    const newManager = await this.Rebalancer.rebalancerManager.call();
    newManager.should.be.equal(manager);
    // it will revert with unspecified reason for nonOwner
    await expectRevert.unspecified(this.Rebalancer.setRebalancerManager(val, { from: nonOwner }));
  });
  it('allows onlyOwner to setSaver', async function () {
    const val = this.addr1;
    // it will revert with reason `s addr already set` because it has already been set in beforeEach
    await expectRevert(
      this.Rebalancer.setSaver(val, { from: creator }),
      'saver addr already set'
    );

    // it will revert with unspecified reason for nonOwner
    await expectRevert.unspecified(this.Rebalancer.setSaver(val, { from: nonOwner }));
  });
  it('do not allow onlyOwner to setNewToken if the token is already present', async function () {
    const val = this.addr1;
    await this.Rebalancer.setNewToken(val, { from: creator });
    // Test length
    await expectRevert(this.Rebalancer.lastAmountsAddresses.call(4), "invalid opcode");
    await expectRevert(this.Rebalancer.lastAmounts.call(4), "invalid opcode");
    // it will revert with unspecified reason for nonOwner
    await expectRevert.unspecified(this.Rebalancer.setNewToken(val, { from: nonOwner }));
  });
  it('allows onlyOwner to setNewToken if the token is new', async function () {
    const val = this.addrNew;
    await this.Rebalancer.setNewToken(val, { from: creator });
    const newVal = await this.Rebalancer.lastAmountsAddresses.call(2);
    newVal.should.be.equal(val);
    // No exception
    const newAmount = await this.Rebalancer.lastAmounts.call(2);
    newAmount.should.be.bignumber.equal(BNify('0'));
    // it will revert with unspecified reason for nonOwner
    await expectRevert.unspecified(this.Rebalancer.setNewToken(val, { from: nonOwner }));
  });
  it('getAllocations', async function () {
    const alloc = await this.Rebalancer.getAllocations();
    alloc[0].should.be.bignumber.equal(BNify('100000'));
    alloc[1].should.be.bignumber.equal(BNify('0'));
  });
  it('allows onlyRebalancer and saver to setAllocations', async function () {
    await this.Rebalancer.setAllocations(
      [BNify('50000'), BNify('50000')],
      [this.addr1, this.addr2],
      { from: manager }
    );
    (await this.Rebalancer.lastAmounts(0)).should.be.bignumber.equal(BNify('50000'));
    (await this.Rebalancer.lastAmounts(1)).should.be.bignumber.equal(BNify('50000'));

    await this.Rebalancer.setAllocations(
      [BNify('20000'), BNify('80000')],
      [this.addr1, this.addr2],
      { from: saver }
    );
    (await this.Rebalancer.lastAmounts(0)).should.be.bignumber.equal(BNify('20000'));
    (await this.Rebalancer.lastAmounts(1)).should.be.bignumber.equal(BNify('80000'));

    await expectRevert(
      this.Rebalancer.setAllocations(
        [BNify('5000'), BNify('0')],
        [this.addr1, this.addr2],
        { from: manager }
      ),
      'NOT 100%'
    );

    await expectRevert(
      this.Rebalancer.setAllocations(
        [BNify('5000'), BNify('5000')],
        [this.addr1, this.addr2, this.addr3],
        { from: manager }
      ),
      'length != _addresses'
    );
    await expectRevert(
      this.Rebalancer.setAllocations(
        [BNify('5000'), BNify('0')],
        // swapped addresses
        [this.addr2, this.addr1],
        { from: manager }
      ),
      'Address not match'
    );

    // it will revert with unspecified reason if called from a non rebalancer manager
    await expectRevert.unspecified(
      this.Rebalancer.setAllocations([BNify('0')], [this.addr1], { from: nonOwner })
    );
  });
});
