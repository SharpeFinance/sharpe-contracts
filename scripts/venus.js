
// test vBUSD
require('./adaptor')
  .main(
    ['VenusAdaptor'],
    // '0x8301f2213c0eed49a7e28ae4c3e91722919b8b47',
    // '0x08e0a5575de71037ae36abfafb516595fe68e5e4',
    // 1e18
  )
  .catch(err => console.log(err));