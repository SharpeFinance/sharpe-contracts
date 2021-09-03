
const poolInfo = {
  cashPerShare: 0,
  loanPerShare: 0,
  lastTime: 0,
  totalAmount: 0,
  shares: 0
}

const userInfoA = {
  shares: 0,
  allAmount: 0,
}

const userInfoB = {
  shares: 0,
  allAmount: 0,
}

const allUsers = [userInfoA, userInfoB]



function updatePool(poolInfo) {
  if (poolInfo.lastTime == 0) {
    poolInfo.lastTime = Date.now();
  } else {
    const duration = Date.now() - poolInfo.lastTime;
    const interestRate =  0.00001 * duration;
    console.log('interestRate', interestRate, duration)

  }
}

function deposit(amount, userInfo) {

  updatePool(poolInfo);

  let sharesToAdd = 0;
  if (poolInfo.shares == 0) {
    sharesToAdd = amount;
  } else {
    sharesToAdd = amount * poolInfo.shares / poolInfo.shares;
  }

  poolInfo.shares += sharesToAdd
  userInfo.shares += sharesToAdd

  poolInfo.totalAmount += amount;
  userInfo.allAmount += amount;

  // update
  poolInfo.cashPerShare = poolInfo.totalAmount / poolInfo.shares;

  console.log('poolInfo', poolInfo)
  console.log('allUsers', allUsers.map(_ => 
    Object.assign(
      _, 
      {
        holdAmount: _.shares * poolInfo.cashPerShare
      }
    )
  ))
}

deposit(2, userInfoA);
deposit(10, userInfoB);
deposit(100, userInfoB);
setTimeout(function() {
  deposit(1000, userInfoA);
}, 1000)