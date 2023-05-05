// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Owned.sol";

interface IStarToken {
    function farmMint(address account, uint256 amount) external;
}

interface IBonus {
    function getlockRatio() view external returns (uint256);
    function addTotalAmount(uint256) external;
    function addXTotalAmount(uint256) external;
}

interface IStarNode {
    function nodeGain(address _user) external view returns (uint256, uint256);
    function settleNode(address _user, uint256 _amount, uint256 _selfAmount, uint256 _xamount, uint256 _xselfAmount) external;
    function settleNodeLp(address _user, IERC20 lpAddr, uint256 _parentAmountLp, uint256 _selfAmountLp) external;
}

interface IMasterChef {
    function userInfo(uint256 _pid, address _user) external view returns(
        uint256 amount,
        uint256 rewardDebt,
        uint256 lastDeposit,
        uint256 nftAmount,
        uint256 nftRewardDebt,
        uint256 nftLastDeposit
        );
    function userLpInfo(uint256 _pid, address _user) external view returns(
        uint256 lpRewardDebt,
        uint256 lpTwoRewardDebt,
        uint256 lpThrRewardDebt,
        uint256 nftLpRewardDebt,
        uint256 nftLpTwoRewardDebt,
        uint256 nftLpThrRewardDebt
    );
    function isNodeUser(address _user) external view returns (bool);
    function setPoolUser(uint256 _pid, address _user) external;
    function setUserIndex(uint256 _pid, uint256 _size, address _user) external;
}

interface IFarmLib {
    function migrate(IERC20 token) external returns (IERC20);
}

interface IXToken {
    function farmConvert(address _account, uint256 _amount) external;
}

contract FarmLib is owned {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lpRewardDebt;
        uint256 lpTwoRewardDebt;
        uint256 lpThrRewardDebt;
        uint256 lastDeposit;
        uint256 nftAmount;
        uint256 nftRewardDebt;
        uint256 nftLastDeposit;
        uint256 nftLpRewardDebt;
        uint256 nftLpTwoRewardDebt;
        uint256 nftLpThrRewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;  // Address of LP token contract.
        address xToken;
        uint256 lpSupply;
        uint256 allocPoint;         // How many allocation points assigned to this pool. STARs to distribute per block.
        uint256 lastRewardBlock;    // Last block number that STARs distribution occurs.
        uint256 accStarPerShare;    // Accumulated STARs per share, times 1e22. See below.
        uint256 extraAmount;        // Extra amount of token. users from node or NFT.
        uint256 fee;
        uint256 size;
        uint256 deflationRate;
        uint256 xRate;
        uint256 bond;
    }

    struct PoolLpInfo {
        bool isExtra;
        bool isTwoExtra;
        bool isThrExtra;
        IERC20 lpAddr;
        IERC20 lpTwoAddr;
        IERC20 lpThrAddr;
        uint256 lpPerBlock;
        uint256 lpTwoPerBlock;
        uint256 lpThrPerBlock;
        uint256 accLpPerShare;
        uint256 accLpTwoPerShare;
        uint256 accLpThrPerShare;
    }

    struct BlockReward {
        uint256 plannedBlock;
        uint256 plannedReward;
    }

    struct AllocationInfo{
        address lockAddr;
        address teamAddr;
        address rewardAddr;
        uint256 lockRatio;
        uint256 teamRatio;
        uint256 rewardRatio;
    }

    struct SlotInfo {
        uint256 _amount;
        uint256 _amountGain;
        uint256 _selfGain;
        uint256 _parentGain;
        uint256 _self_parentGain;
        uint256 withdrawAmount;
        uint256 xwithdrawAmount;
        bool success;
        uint256 fee;
        uint256 amountBonus;
        uint256 xfee;
        uint256 xamountBonus;
        uint256 _userAmount;
        uint256 _nodeAmount;
    }

    // STAR tokens created per block.
    uint256 public starPerBlock;
    // Bonus muliplier for early star makers.
    uint256 public BONUS_MULTIPLIER;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when STAR mining starts.
    uint256 public startBlock;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IFarmLib public migrator;

    // The STAR TOKEN!
    IERC20 public starToken;
    IStarToken public iToken;
    // Bonus address.
    address public bonusAddr;
    //StarNode
    IStarNode public starNode;
    //StarFarm
    IMasterChef public starFarm;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    PoolLpInfo[] public poolLpInfo;
    BlockReward[] public blockReward;
    AllocationInfo public alloc;

    event Withdraw(address indexed user, uint256 indexed pid, uint256 pending, uint256 xPending, bool isNodeUser, uint256 amount);
    event Received(address, uint);

    constructor(address _starToken, address _xToken, address _bonus, address _node, uint256 _starPerBlock, uint256 _startBlock) {
        starToken = IERC20(_starToken);
        iToken = IStarToken(_starToken);
        bonusAddr = _bonus;
        starNode = IStarNode(_node);
        starPerBlock = _starPerBlock;
        startBlock = _startBlock;
        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: starToken,
            xToken: _xToken,
            lpSupply: 0,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accStarPerShare: 0,
            extraAmount: 0,
            fee: 0,
            size: 0,
            deflationRate: 0,
            xRate: 0,
            bond: 0
        }));
        poolLpInfo.push(PoolLpInfo({
            isExtra: false,
            isTwoExtra: false,
            isThrExtra: false,
            lpAddr: IERC20(address(0)),
            lpTwoAddr: IERC20(address(0)),
            lpThrAddr: IERC20(address(0)),
            lpPerBlock: 0,
            lpTwoPerBlock: 0,
            lpThrPerBlock: 0,
            accLpPerShare: 0,
            accLpTwoPerShare: 0,
            accLpThrPerShare: 0
        }));

        totalAllocPoint = 1000;
        BONUS_MULTIPLIER = 1;
    }

    // Harvest execution method
    function harvest(uint256 _pid, address _user, uint256 _amount, bool isNFT) external onlyStarFarm {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo memory user;
        SlotInfo memory slot;
        (user.amount, user.rewardDebt, user.lastDeposit, user.nftAmount, user.nftRewardDebt, ) = starFarm.userInfo(_pid, _user);
        (slot._selfGain, slot._parentGain) = starNode.nodeGain(_user);
        uint256 pending;
        uint256 xPending;
        slot._self_parentGain = slot._selfGain.add(slot._parentGain);
        if(isNFT == false){
            slot._amountGain = user.amount.add(user.amount.mul(slot._self_parentGain).div(100));
            pending = slot._amountGain.mul(pool.accStarPerShare).div(1e22).sub(user.rewardDebt);
        }else{
            slot._amountGain = user.nftAmount.add(user.nftAmount.mul(slot._self_parentGain).div(100));
            pending = slot._amountGain.mul(pool.accStarPerShare).div(1e22).sub(user.nftRewardDebt);
        }
        if(pool.xRate > 0){
            xPending = pending.mul(pool.xRate).div(10000);
            pending = pending.sub(xPending);
        }
        if(pending > 0 || xPending > 0) {
            if(pending > 0){
                iToken.farmMint(address(this), pending);
                starToken.safeTransfer(alloc.lockAddr,pending.mul(alloc.lockRatio).div(10000));
                starToken.safeTransfer(alloc.teamAddr,pending.mul(alloc.teamRatio).div(10000));
                pending = pending.sub(pending.mul(alloc.lockRatio.add(alloc.teamRatio)).div(10000));
                starToken.safeTransfer(alloc.rewardAddr,pending.mul(alloc.rewardRatio).div(10000));
                pending = pending.sub(pending.mul(alloc.rewardRatio).div(10000));
                pending = pending.mul(100).div(slot._self_parentGain.add(100));
            }
            if(xPending > 0){
                iToken.farmMint(address(this), xPending);
                starToken.safeTransfer(pool.xToken, xPending);
                IXToken(pool.xToken).farmConvert(alloc.lockAddr,xPending.mul(alloc.lockRatio).div(10000));
                IXToken(pool.xToken).farmConvert(alloc.teamAddr,xPending.mul(alloc.teamRatio).div(10000));
                xPending = xPending.sub(xPending.mul(alloc.lockRatio.add(alloc.teamRatio)).div(10000));
                IXToken(pool.xToken).farmConvert(alloc.rewardAddr,xPending.mul(alloc.rewardRatio).div(10000));
                xPending = xPending.sub(xPending.mul(alloc.rewardRatio).div(10000));
                xPending = xPending.mul(100).div(slot._self_parentGain.add(100));
            }
            if (user.lastDeposit > block.timestamp.sub(2592000) && isNFT == false) {
                slot.fee = pending.mul(pool.fee).div(10000);
                slot.xfee = xPending.mul(pool.fee).div(10000);
                slot.withdrawAmount = (pending.sub(slot.fee)).mul(slot._selfGain.add(100)).div(100);
                slot.xwithdrawAmount = (xPending.sub(slot.xfee)).mul(slot._selfGain.add(100)).div(100);
                starToken.safeTransfer(_user, (pending.sub(slot.fee)));
                if(xPending>0)IXToken(pool.xToken).farmConvert(_user, xPending.sub(slot.xfee));
                if(slot._self_parentGain > 0){
                    starToken.safeTransfer(address(starNode), (pending.sub(slot.fee).mul(slot._self_parentGain).div(100)));
                    if(xPending>0)IXToken(pool.xToken).farmConvert(address(starNode), xPending.sub(slot.xfee).mul(slot._self_parentGain).div(100));
                    starNode.settleNode(_user, (pending.sub(slot.fee).mul(slot._parentGain).div(100)), (pending.sub(slot.fee).mul(slot._selfGain).div(100)), (xPending.sub(slot.fee).mul(slot._parentGain).div(100)), (xPending.sub(slot.fee).mul(slot._selfGain).div(100)));
                }
                if(pool.fee > 0){
                    IBonus Bonus = IBonus(bonusAddr);
                    slot.fee = slot.fee.add(slot.fee.mul(slot._self_parentGain).div(100));
                    slot.xfee = slot.xfee.add(slot.xfee.mul(slot._self_parentGain).div(100));
                    starToken.safeTransfer(alloc.lockAddr, slot.fee.mul(Bonus.getlockRatio()).div(100));
                    slot.amountBonus = slot.fee.sub(slot.fee.mul(Bonus.getlockRatio()).div(100));
                    slot.xamountBonus = slot.xfee.sub(slot.xfee.mul(Bonus.getlockRatio()).div(100));
                    starToken.safeTransfer(bonusAddr, slot.amountBonus);
                    if(xPending>0)IXToken(pool.xToken).farmConvert(bonusAddr, slot.xamountBonus);
                    Bonus.addTotalAmount(slot.amountBonus);
                    Bonus.addXTotalAmount(slot.xamountBonus);
                }
            }else{
                slot.withdrawAmount = pending;
                slot.xwithdrawAmount = xPending;
                starToken.safeTransfer(_user, pending);
                if(xPending>0)IXToken(pool.xToken).farmConvert(_user, xPending);
                if(slot._self_parentGain > 0){
                    starToken.safeTransfer(address(starNode), pending.mul(slot._self_parentGain).div(100));
                    if(xPending>0)IXToken(pool.xToken).farmConvert(address(starNode), xPending.mul(slot._self_parentGain).div(100));
                }
                starNode.settleNode(_user, pending.mul(slot._parentGain).div(100), pending.mul(slot._selfGain).div(100), xPending.mul(slot._parentGain).div(100), xPending.mul(slot._selfGain).div(100));
            }
            emit Withdraw(_user, _pid, slot.withdrawAmount, slot.xwithdrawAmount, starFarm.isNodeUser(_user), _amount);
        }
    }

    function harvestLp(uint256 _pid, address _user, bool isNFT) external onlyStarFarm {
        PoolInfo storage pool = poolInfo[_pid];
        PoolLpInfo storage poolLp = poolLpInfo[_pid];
        UserInfo memory user;
        SlotInfo memory slot;
        (user.amount, user.rewardDebt, user.lastDeposit, user.nftAmount, user.nftRewardDebt, ) = starFarm.userInfo(_pid, _user);
        (user.lpRewardDebt, user.lpTwoRewardDebt, user.lpThrRewardDebt, user.nftLpRewardDebt, user.nftLpTwoRewardDebt, user.nftLpThrRewardDebt) = starFarm.userLpInfo(_pid, _user);
        (slot._selfGain, slot._parentGain) = starNode.nodeGain(_user);
        slot._self_parentGain = slot._selfGain.add(slot._parentGain);
        uint256 lpPending;
        uint256 lpTwoPending;
        uint256 lpThrPending;
        if(isNFT == false){
            slot._amountGain = user.amount.add(user.amount.mul(slot._self_parentGain).div(100));
            lpPending = slot._amountGain.mul(poolLp.accLpPerShare).div(1e22).sub(user.lpRewardDebt);
            lpTwoPending = slot._amountGain.mul(poolLp.accLpTwoPerShare).div(1e22).sub(user.lpTwoRewardDebt);
            lpThrPending = slot._amountGain.mul(poolLp.accLpThrPerShare).div(1e22).sub(user.lpThrRewardDebt);
        }else{
            slot._amountGain = user.nftAmount.add(user.nftAmount.mul(slot._self_parentGain).div(100));
            lpPending = slot._amountGain.mul(poolLp.accLpPerShare).div(1e22).sub(user.nftLpRewardDebt);
            lpTwoPending = slot._amountGain.mul(poolLp.accLpTwoPerShare).div(1e22).sub(user.nftLpTwoRewardDebt);
            lpThrPending = slot._amountGain.mul(poolLp.accLpThrPerShare).div(1e22).sub(user.nftLpThrRewardDebt);
        }
        uint256 _parentLp;
        uint256 _selfLp;
        uint256 lpFee;
        if(lpPending > 0 && poolLp.isExtra == true) {
            lpPending = lpPending.mul(100).div(slot._self_parentGain.add(100));
            if (user.lastDeposit > block.timestamp.sub(2592000) && isNFT == false) {
                lpFee = lpPending.mul(pool.fee).div(10000);
                if(address(poolLp.lpAddr) == address(0)){
                    slot._userAmount = lpPending.sub(lpFee);
                    if(slot._self_parentGain > 0){
                        slot._nodeAmount = lpPending.sub(lpFee).mul(slot._self_parentGain).div(100);
                    }
                }else{
                    poolLp.lpAddr.safeTransfer(_user, (lpPending.sub(lpFee)));
                    if(slot._self_parentGain > 0)poolLp.lpAddr.safeTransfer(address(starNode), (lpPending.sub(lpFee).mul(slot._self_parentGain).div(100)));
                }
                _parentLp = lpPending.sub(lpFee).mul(slot._parentGain).div(100);
                _selfLp = lpPending.sub(lpFee).mul(slot._selfGain).div(100);
            }else{
                if(address(poolLp.lpAddr) == address(0)){
                    slot._userAmount = lpPending;
                    if(slot._self_parentGain > 0){
                        slot._nodeAmount = lpPending.mul(slot._self_parentGain).div(100);
                    }
                }else{
                    poolLp.lpAddr.safeTransfer(_user, lpPending);
                    poolLp.lpAddr.safeTransfer(address(starNode), lpPending.mul(slot._self_parentGain).div(100));
                }
                _parentLp = lpPending.mul(slot._parentGain).div(100);
                _selfLp = lpPending.mul(slot._selfGain).div(100);
            }
            starNode.settleNodeLp(_user, poolLp.lpAddr, _parentLp, _selfLp);
        }
        if(lpTwoPending > 0 && poolLp.isTwoExtra == true) {
            lpTwoPending = lpTwoPending.mul(100).div(slot._self_parentGain.add(100));
            if (user.lastDeposit > block.timestamp.sub(2592000) && isNFT == false) {
                lpFee = lpTwoPending.mul(pool.fee).div(10000);
                if(address(poolLp.lpTwoAddr) == address(0)){
                    slot._userAmount = slot._userAmount.add(lpTwoPending.sub(lpFee));
                    if(slot._self_parentGain > 0){
                        slot._nodeAmount = slot._nodeAmount.add(lpTwoPending.sub(lpFee).mul(slot._self_parentGain).div(100));
                    }
                }else{
                    poolLp.lpTwoAddr.safeTransfer(_user, (lpTwoPending.sub(lpFee)));
                    if(slot._self_parentGain > 0)poolLp.lpTwoAddr.safeTransfer(address(starNode), (lpTwoPending.sub(lpFee).mul(slot._self_parentGain).div(100)));
                }
                _parentLp = lpTwoPending.sub(lpFee).mul(slot._parentGain).div(100);
                _selfLp = lpTwoPending.sub(lpFee).mul(slot._selfGain).div(100);
            }else{
                if(address(poolLp.lpTwoAddr) == address(0)){
                    slot._userAmount = slot._userAmount.add(lpTwoPending);
                    if(slot._self_parentGain > 0){
                        slot._nodeAmount = slot._nodeAmount.add(lpTwoPending.mul(slot._self_parentGain).div(100));
                    }
                }else{
                    poolLp.lpTwoAddr.safeTransfer(_user, lpTwoPending);
                    poolLp.lpTwoAddr.safeTransfer(address(starNode), lpTwoPending.mul(slot._self_parentGain).div(100));
                }
                _parentLp = lpTwoPending.mul(slot._parentGain).div(100);
                _selfLp = lpTwoPending.mul(slot._selfGain).div(100);
            }
            starNode.settleNodeLp(_user, poolLp.lpTwoAddr, _parentLp, _selfLp);
        }
        if(lpThrPending > 0 && poolLp.isThrExtra == true) {
            lpThrPending = lpThrPending.mul(100).div(slot._self_parentGain.add(100));
            if (user.lastDeposit > block.timestamp.sub(2592000) && isNFT == false) {
                lpFee = lpThrPending.mul(pool.fee).div(10000);
                if(address(poolLp.lpThrAddr) == address(0)){
                    slot._userAmount = slot._userAmount.add(lpThrPending.sub(lpFee));
                    if(slot._self_parentGain > 0){
                        slot._nodeAmount = slot._nodeAmount.add(lpThrPending.sub(lpFee).mul(slot._self_parentGain).div(100));
                    }
                }else{
                    poolLp.lpThrAddr.safeTransfer(_user, (lpThrPending.sub(lpFee)));
                    if(slot._self_parentGain > 0)poolLp.lpThrAddr.safeTransfer(address(starNode), (lpThrPending.sub(lpFee).mul(slot._self_parentGain).div(100)));
                }
                _parentLp = lpThrPending.sub(lpFee).mul(slot._parentGain).div(100);
                _selfLp = lpThrPending.sub(lpFee).mul(slot._selfGain).div(100);
            }else{
                if(address(poolLp.lpThrAddr) == address(0)){
                    slot._userAmount = slot._userAmount.add(lpThrPending);
                    if(slot._self_parentGain > 0){
                        slot._nodeAmount = slot._nodeAmount.add(lpThrPending.mul(slot._self_parentGain).div(100));
                    }
                }else{
                    poolLp.lpThrAddr.safeTransfer(_user, lpThrPending);
                    poolLp.lpThrAddr.safeTransfer(address(starNode), lpThrPending.mul(slot._self_parentGain).div(100));
                }
                _parentLp = lpThrPending.mul(slot._parentGain).div(100);
                _selfLp = lpThrPending.mul(slot._selfGain).div(100);
            }
            starNode.settleNodeLp(_user, poolLp.lpThrAddr, _parentLp, _selfLp);
        }
        if(slot._userAmount > 0){
            (slot.success, ) = _user.call{value:slot._userAmount}("");
            require(slot.success, "");
            if(slot._self_parentGain > 0){
                (slot.success, ) = address(starNode).call{value:slot._nodeAmount}("");
                require(slot.success, "");
            }
        }
    }

    // Update Multiplier
    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        massUpdatePools();
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken, 
        address _xToken, 
        uint256 _fee, 
        bool _withUpdate, 
        uint256 _deflationRate, 
        uint256 _xRate, 
        uint256 _bond
    ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.timestamp > startBlock ? block.timestamp : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            xToken: _xToken,
            lpSupply: 0,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accStarPerShare: 0,
            extraAmount: 0,
            fee: _fee,
            size: 0,
            deflationRate: _deflationRate,
            xRate: _xRate,
            bond: _bond
        }));
        poolLpInfo.push(PoolLpInfo({
            isExtra: false,
            isTwoExtra: false,
            isThrExtra: false,
            lpAddr: IERC20(address(0)),
            lpTwoAddr: IERC20(address(0)),
            lpThrAddr: IERC20(address(0)),
            lpPerBlock: 0,
            lpTwoPerBlock: 0,
            lpThrPerBlock: 0,
            accLpPerShare: 0,
            accLpTwoPerShare: 0,
            accLpThrPerShare: 0
        }));
    }

    // Update the given pool's STAR allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint, 
        IERC20 _lpToken, 
        address _xToken, 
        uint256 _fee, 
        bool _withUpdate, 
        uint256 _deflationRate, 
        uint256 _xRate, 
        uint256 _bond
    ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].lpToken = _lpToken;
        poolInfo[_pid].xToken = _xToken;
        poolInfo[_pid].fee = _fee;
        poolInfo[_pid].deflationRate = _deflationRate;
        poolInfo[_pid].xRate = _xRate;
        poolInfo[_pid].bond = _bond;
    }

    function setLpInfo(uint256 _pid, bool _isExtra, IERC20 _lpAddr, uint256 _lpPerBlock) external onlyOwner {
        poolLpInfo[_pid].lpAddr = _lpAddr;
        poolLpInfo[_pid].lpPerBlock = _lpPerBlock;
        poolLpInfo[_pid].isExtra = _isExtra;
    }

    function setLpTwoInfo(uint256 _pid, bool _isTwoExtra, IERC20 _lpTwoAddr, uint256 _lpTwoPerBlock) external onlyOwner {
        poolLpInfo[_pid].lpTwoAddr = _lpTwoAddr;
        poolLpInfo[_pid].lpTwoPerBlock = _lpTwoPerBlock;
        poolLpInfo[_pid].isTwoExtra = _isTwoExtra;
    }

    function setLpThrInfo(uint256 _pid, bool _isThrExtra, IERC20 _lpThrAddr, uint256 _lpThrPerBlock) external onlyOwner {
        poolLpInfo[_pid].lpThrAddr = _lpThrAddr;
        poolLpInfo[_pid].lpThrPerBlock = _lpThrPerBlock;
        poolLpInfo[_pid].isThrExtra = _isThrExtra;
    }

    // Delete the specified pool
    function delPool(uint256 _pid) external onlyOwner {
        require(poolInfo[_pid].lpSupply == 0, "LpSupply exists");
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint);
        poolInfo[_pid] = poolInfo[poolInfo.length - 1];
        poolInfo.pop();
        poolLpInfo[_pid] = poolLpInfo[poolLpInfo.length - 1];
        poolLpInfo.pop();
    }

    // Add the specified preset starPerBlock
    function addBlockReward(uint256 _block, uint256 _reward) external onlyOwner {
        require(_block > block.timestamp,"block error");
        blockReward.push(BlockReward({
            plannedBlock: _block,
            plannedReward: _reward
            }));
    }

    // Set the specified preset starPerBlock
    function setBlockReward(uint256 _rid, uint256 _block, uint256 _reward) external onlyOwner {
        BlockReward storage breward = blockReward[_rid];
        require(_block > block.timestamp && breward.plannedBlock > block.timestamp,"block error");
        breward.plannedBlock = _block;
        breward.plannedReward = _reward;
    }

    // Delete the specified preset starPerBlock
    function delBlockReward(uint256 _rid) external onlyOwner {
        for(uint256 i; i< blockReward.length; i++){
            if(i == _rid){
                blockReward[i] = blockReward[blockReward.length - 1];
                blockReward.pop();
            }
        }
    }

    // Update starPerBlock
    function updatePerBlock(uint256 _i) private {
        for(uint256 i = 0; i < poolInfo.length; i++){
            PoolInfo storage pool = poolInfo[i];
            PoolLpInfo storage poolLp = poolLpInfo[i];
            if(pool.lastRewardBlock > blockReward[_i].plannedBlock){
                continue;
            }
            uint256 lpSupply = pool.lpSupply.add(pool.extraAmount);
            if (blockReward[_i].plannedBlock > pool.lastRewardBlock && lpSupply != 0) {
                uint256 multiplier = getMultiplier(pool.lastRewardBlock, blockReward[_i].plannedBlock);
                uint256 starReward = multiplier.mul(starPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                uint256 lpReward = multiplier.mul(poolLp.lpPerBlock);
                uint256 lpTwoReward = multiplier.mul(poolLp.lpTwoPerBlock);
                pool.accStarPerShare = pool.accStarPerShare.add(starReward.mul(1e22).div(lpSupply));
                if(poolLp.isExtra == true)poolLp.accLpPerShare = poolLp.accLpPerShare.add(lpReward.mul(1e22).div(lpSupply));
                if(poolLp.isTwoExtra == true)poolLp.accLpTwoPerShare = poolLp.accLpTwoPerShare.add(lpTwoReward.mul(1e22).div(lpSupply));
                pool.lastRewardBlock = blockReward[_i].plannedBlock;
                return;
            }
        }
        starPerBlock = blockReward[_i].plannedReward;
    }

    // Update lpAddr
    function updatelpPerBlock(uint256 _pid, address _lpAddr , uint256 _lpPerBlock) external onlyOwner {
        massUpdatePools();
        PoolLpInfo storage poolLp = poolLpInfo[_pid];
        poolLp.lpAddr = IERC20(_lpAddr);
        poolLp.lpPerBlock = _lpPerBlock;
    }

    function updatelpTwoPerBlock(uint256 _pid, address _lpTwoAddr , uint256 _lpTwoPerBlock) external onlyOwner {
        massUpdatePools();
        PoolLpInfo storage poolLp = poolLpInfo[_pid];
        poolLp.lpTwoAddr = IERC20(_lpTwoAddr);
        poolLp.lpTwoPerBlock = _lpTwoPerBlock;
    }

    function updatelpThrPerBlock(uint256 _pid, address _lpThrAddr , uint256 _lpThrPerBlock) external onlyOwner {
        massUpdatePools();
        PoolLpInfo storage poolLp = poolLpInfo[_pid];
        poolLp.lpThrAddr = IERC20(_lpThrAddr);
        poolLp.lpThrPerBlock = _lpThrPerBlock;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IFarmLib _migrator) external onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. We trust that migrator contract is good.
    function migrate(uint256 _pid) external onlyOwner {
        require(address(migrator) != address(0), "no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "bad");
        pool.lpToken = newLpToken;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Loop update starPerBlock
    function reckon() public {
        uint256 len = blockReward.length;
        if(len == 0){
            return;
        }
        for(uint256 i; i < len; i++){
            if(block.timestamp >= blockReward[i].plannedBlock){
                updatePerBlock(i);
            }
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        PoolLpInfo storage poolLp = poolLpInfo[_pid];
        if (block.timestamp <= pool.lastRewardBlock) {
            return;
        }
        if (pool.lpSupply == 0) {
            pool.lastRewardBlock = block.timestamp;
            return;
        }
        reckon();
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.timestamp);
        uint256 starReward = multiplier.mul(starPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 lpReward = multiplier.mul(poolLp.lpPerBlock);
        uint256 lpTwoReward = multiplier.mul(poolLp.lpTwoPerBlock);
        uint256 lpThrReward = multiplier.mul(poolLp.lpThrPerBlock);
        uint256 lpSupply = pool.lpSupply.add(pool.extraAmount);
        pool.accStarPerShare = pool.accStarPerShare.add(starReward.mul(1e22).div(lpSupply));
        poolLp.accLpPerShare = poolLp.accLpPerShare.add(lpReward.mul(1e22).div(lpSupply));
        poolLp.accLpTwoPerShare = poolLp.accLpTwoPerShare.add(lpTwoReward.mul(1e22).div(lpSupply));
        poolLp.accLpThrPerShare = poolLp.accLpThrPerShare.add(lpThrReward.mul(1e22).div(lpSupply));
        pool.lastRewardBlock = block.timestamp;
    }

    // Set the specified dividend address and proportion
    function setAllocationInfo(address _lockAddr,address _teamAddr,address _rewardAddr,uint256 _lockRatio,uint256 _teamRatio,uint256 _rewardRatio) external onlyOwner {
        alloc.lockAddr = _lockAddr;
        alloc.teamAddr = _teamAddr;
        alloc.rewardAddr = _rewardAddr;
        alloc.lockRatio = _lockRatio;
        alloc.teamRatio = _teamRatio;
        alloc.rewardRatio = _rewardRatio;
    }

    function updateStartBlock(uint256 _startBlock) external onlyStarFarm {
        require(startBlock == 0);
		startBlock = _startBlock;
	}

    function setExtraAmount(uint256 _pid, uint256 _extraAmount) external onlyStarFarm {
        poolInfo[_pid].extraAmount = _extraAmount;
    }

    function setLpSupply(uint256 _pid, uint256 _lpSupply) external onlyStarFarm {
        poolInfo[_pid].lpSupply = _lpSupply;
    }

    function setSize(uint256 _pid, uint256 _size) external onlyStarFarm {
        poolInfo[_pid].size = _size;
    }

    function setStarFarm(address _addr) public onlyOwner{
        require(address(0) != _addr);
        starFarm = IMasterChef(_addr);
    }

    // Set starToken address
    function setToken(address _tokenaddr) external onlyOwner {
        starToken = IERC20(_tokenaddr);
        iToken = IStarToken(_tokenaddr);
        poolInfo[0].lpToken = IERC20(_tokenaddr);
    }

    // Set bonus address
    function setBonus(address _addr) external onlyOwner {
        require(address(0) != _addr);
        bonusAddr = _addr;
    }

    // Set starNode address
    function setNode(address _node) external onlyOwner {
        require(address(0) != _node);
        starNode = IStarNode(_node);
    }

    modifier onlyStarFarm() {
        require(_msgSender() == address(starFarm), "not farm");
        _;
    }

    receive() external payable{
        emit Received(_msgSender(), msg.value);
    }
}