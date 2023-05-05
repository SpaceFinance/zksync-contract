// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Owned.sol";

interface IStarNode {
    function nodeGain(address _user) external view returns (uint256, uint256);
}

interface INFTLogic {
    function starMeta(uint256 _tokenId) view external returns (uint8, uint256, uint256, uint256);
    // @error Exception to be handled
}

interface IAirdrop {
    function setUser(address _user, uint256 _type) external;
}

interface IFarmLib{
    function poolInfo(uint256 _pid) external view returns(
        IERC20 lpToken,
        address xToken,
        uint256 lpSupply,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint256 accStarPerShare,
        uint256 extraAmount,
        uint256 fee,
        uint256 size,
        uint256 deflationRate,
        uint256 xRate,
        uint256 bond
    );
    function poolLpInfo(uint256 _pid) external view returns(
        bool isExtra,
        bool isTwoExtra,
        bool isThrExtra,
        IERC20 lpAddr,
        IERC20 lpTwoAddr,
        IERC20 lpThrAddr,
        uint256 lpPerBlock,
        uint256 lpTwoPerBlock,
        uint256 lpThrPerBlock,
        uint256 accLpPerShare,
        uint256 accLpTwoPerShare,
        uint256 accLpThrPerShare
    );

    function poolLength() external view returns (uint256);
    function startBlock() external view returns (uint256);
    function lpPerBlock() external view returns (uint256);
    function updatePool(uint256 _pid) external;
    function updateStartBlock(uint256 _startBlock) external;
    function setExtraAmount(uint256 _pid, uint256 _extraAmount) external;
    function setLpSupply(uint256 _pid, uint256 _lpSupply) external;
    function setSize(uint256 _pid, uint256 _size) external;
    function harvest(uint256 _pid, address _user, uint256 _amount, bool isNFT) external;
    function harvestLp(uint256 _pid, address _user, bool isNFT) external;
}

// MasterChef is the master of Star. He can make Star and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once STAR is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is owned {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lastDeposit;
        uint256 nftAmount;
        uint256 nftRewardDebt;
        uint256 nftLastDeposit;
        //
        // We do some fancy math here. Basically, any point in time, the amount of STARs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accStarPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accStarPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct UserLpInfo {
        uint256 lpRewardDebt;
        uint256 lpTwoRewardDebt;
        uint256 lpThrRewardDebt;
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
        uint256 accLpPerShare;
        uint256 accLpTwoPerShare;
        uint256 accLpThrPerShare;
    }

    struct SlotInfo {
        uint256 _amountGain;
        uint256 _selfGain;
        uint256 _parentGain;
        uint256 _self_parentGain;
        uint256 withdrawAmount;
        uint256 _userNFTsIndex;
        uint256 StakingNFTsIndex;
        uint256 NFTGroupIndex;
    }

    struct RedeemInfo {
        uint256 amount;
        uint256 endTime;
        uint256 dividendsAllocation;
    }

    // Star node.
    IStarNode public starNode;
    // Star NFT.
    IERC721 public starNFT;
    // NFT logic
    INFTLogic public nftLogic;
    // Bonus muliplier for early star makers.
    IFarmLib public farmLib;

    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (uint256 => mapping (address => UserLpInfo)) public userLpInfo;
    mapping (uint256 => mapping (uint256 => address)) public userIndex;
    mapping (uint256 => mapping (address => bool)) public isPoolUser;

    // Node user
    mapping (address => bool) public isNodeUser;
    IAirdrop public Airdrop;

    mapping (address => uint256[]) public userNFTs;
    uint256[] public StakingNFTs;
    mapping (uint256 => address) public nftUser;
    mapping (uint256 => uint256) public StakingIndex;
    mapping (uint256 => uint256[]) public NFTGroup;
    mapping (uint256 => mapping(uint256 => uint256)) public groupIndex;
    mapping (uint256 => mapping(address => RedeemInfo[])) public userRedeems;
    bool public isDeposit;
    mapping (uint256 => bool) public isNotLp;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, bool isNodeUser);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, bool isNodeUser);
    event Received(address, uint);

    constructor(address _node, address _farmLib) {
        starNode = IStarNode(_node);
        farmLib = IFarmLib(_farmLib);
    }

    function setDeposit(bool _isDeposit) external onlyOwner{
        isDeposit = _isDeposit;
    }

    function addRedeens(uint256 _pid, uint256 _amount) external {
        UserInfo storage user = userInfo[_pid][_msgSender()];
        require(_amount <= user.amount, "amount err");
        PoolInfo memory pool;
        farmLib.updatePool(_pid);
        farmLib.harvest(_pid, _msgSender(), _amount, false);
        farmLib.harvestLp(_pid, _msgSender(), false);
        ( , , pool.lpSupply, , , pool.accStarPerShare, pool.extraAmount, , , , , pool.bond) = farmLib.poolInfo(_pid);
        (, , , , , , , , , pool.accLpPerShare, pool.accLpTwoPerShare, pool.accLpThrPerShare) = farmLib.poolLpInfo(_pid);
        UserLpInfo storage userLp = userLpInfo[_pid][_msgSender()];
        uint256 timestampBond = block.timestamp + pool.bond;
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            uint256 _extraAmount = _amount.mul(_selfGain.add(_parentGain)).div(100);
            farmLib.setExtraAmount(_pid, pool.extraAmount.sub(_extraAmount));
            farmLib.setLpSupply(_pid, pool.lpSupply.sub(_amount));
            userRedeems[_pid][_msgSender()].push(RedeemInfo ({
                amount: _amount,
                endTime: timestampBond,
                dividendsAllocation: 0
            }));
        }
        uint256 _amountGain = user.amount.add(user.amount.mul(_selfGain.add(_parentGain)).div(100));
        user.rewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e22);
        userLp.lpRewardDebt = _amountGain.mul(pool.accLpPerShare).div(1e22);
        userLp.lpTwoRewardDebt = _amountGain.mul(pool.accLpTwoPerShare).div(1e22);
        userLp.lpThrRewardDebt = _amountGain.mul(pool.accLpThrPerShare).div(1e22);
    }

    function delRedeens(uint256 _pid, uint256 _i) external {
        UserInfo storage user = userInfo[_pid][_msgSender()];
        uint256 len = userRedeems[_pid][_msgSender()].length - 1;
        uint256 _amount = userRedeems[_pid][_msgSender()][_i].amount;
        PoolInfo memory pool;
        farmLib.updatePool(_pid);
        farmLib.harvest(_pid, _msgSender(), 0, false);
        farmLib.harvestLp(_pid, _msgSender(), false);
        ( , , pool.lpSupply, , , pool.accStarPerShare, pool.extraAmount, , , , , pool.bond) = farmLib.poolInfo(_pid);
        (, , , , , , , , , pool.accLpPerShare, pool.accLpTwoPerShare, pool.accLpThrPerShare) = farmLib.poolLpInfo(_pid);
        UserLpInfo storage userLp = userLpInfo[_pid][_msgSender()];
        userRedeems[_pid][_msgSender()][_i] = userRedeems[_pid][_msgSender()][len];
        userRedeems[_pid][_msgSender()].pop();
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        if(_amount > 0) {
            user.amount = user.amount.add(_amount);
            uint256 _extraAmount = _amount.mul(_selfGain.add(_parentGain)).div(100);
            farmLib.setExtraAmount(_pid, pool.extraAmount.add(_extraAmount));
            farmLib.setLpSupply(_pid, pool.lpSupply.add(_amount));
        }
        uint256 _amountGain = user.amount.add(user.amount.mul(_selfGain.add(_parentGain)).div(100));
        user.rewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e22);
        userLp.lpRewardDebt = _amountGain.mul(pool.accLpPerShare).div(1e22);
        userLp.lpTwoRewardDebt = _amountGain.mul(pool.accLpTwoPerShare).div(1e22);
        userLp.lpThrRewardDebt = _amountGain.mul(pool.accLpThrPerShare).div(1e22);
    }

    function getRedeens(uint256 _pid) view external returns(RedeemInfo[] memory) {
        return userRedeems[_pid][_msgSender()];
    }

    function getRedeensInfo(uint256 _pid, uint256 _i) view external returns(RedeemInfo memory){
        return userRedeems[_pid][_msgSender()][_i];
    }

    function withdrawRedeens(uint256 _pid, uint256 _i) external {
        require(userRedeems[_pid][_msgSender()].length > 0, "length err");
        require(userRedeems[_pid][_msgSender()][_i].endTime < block.timestamp, "time err");
        uint256 len = userRedeems[_pid][_msgSender()].length - 1;
        uint256 _amount = userRedeems[_pid][_msgSender()][_i].amount;
        PoolInfo memory pool;
        (pool.lpToken, , pool.lpSupply, , , pool.accStarPerShare, pool.extraAmount, , , , ,) = farmLib.poolInfo(_pid);
        userRedeems[_pid][_msgSender()][_i] = userRedeems[_pid][_msgSender()][len];
        userRedeems[_pid][_msgSender()].pop();
        pool.lpToken.safeTransfer(_msgSender(), _amount);
    }

    // Deposit LP tokens to MasterChef for STAR allocation.
    function deposit(uint256 _pid, uint256 _amount) external {
        require(isDeposit == true, "Not started");
        PoolInfo memory pool;
        farmLib.updatePool(_pid);
        farmLib.harvest(_pid, _msgSender(), 0, false);
        farmLib.harvestLp(_pid, _msgSender(), false);
        (pool.lpToken, pool.xToken, pool.lpSupply, , , pool.accStarPerShare, pool.extraAmount, , pool.size, pool.deflationRate, , ) = farmLib.poolInfo(_pid);
        (, , , , , , , , , pool.accLpPerShare, pool.accLpTwoPerShare, pool.accLpThrPerShare) = farmLib.poolLpInfo(_pid);
        UserInfo storage user = userInfo[_pid][_msgSender()];
        UserLpInfo storage userLp = userLpInfo[_pid][_msgSender()];
        if(farmLib.startBlock() == 0){
            farmLib.updateStartBlock(block.timestamp);
        }
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(_msgSender(), address(this), _amount);
            _amount = _amount.sub(_amount.mul(pool.deflationRate).div(10000));
            user.amount = user.amount.add(_amount);
            user.lastDeposit = block.timestamp;
            uint256 _extraAmount = _amount.mul(_selfGain.add(_parentGain)).div(100);
            farmLib.setExtraAmount(_pid, pool.extraAmount.add(_extraAmount));
            farmLib.setLpSupply(_pid, pool.lpSupply.add(_amount));
            if(isPoolUser[_pid][_msgSender()] == false){
                userIndex[_pid][pool.size] = _msgSender();
                farmLib.setSize(_pid, pool.size.add(1));
                isPoolUser[_pid][_msgSender()] = true;
            }
            Airdrop.setUser(_msgSender(),1);
        }
        uint256 _amountGain = user.amount.add(user.amount.mul(_selfGain.add(_parentGain)).div(100));
        user.rewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e22);
        userLp.lpRewardDebt = _amountGain.mul(pool.accLpPerShare).div(1e22);
        userLp.lpTwoRewardDebt = _amountGain.mul(pool.accLpTwoPerShare).div(1e22);
        userLp.lpThrRewardDebt = _amountGain.mul(pool.accLpThrPerShare).div(1e22);
        emit Deposit(_msgSender(), _pid, _amount, isNodeUser[_msgSender()]);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {
        PoolInfo memory pool;
        UserInfo storage user = userInfo[_pid][_msgSender()];
        ( , , , , , , , , , , , pool.bond) = farmLib.poolInfo(_pid);
        require(pool.bond == 0 || _amount == 0, "bond error");
        require(user.amount >= _amount, "amount err");
        farmLib.updatePool(_pid);
        farmLib.harvest(_pid, _msgSender(), _amount, false);
        farmLib.harvestLp(_pid, _msgSender(), false);
        (pool.lpToken, , pool.lpSupply, , , pool.accStarPerShare, pool.extraAmount, , , , ,) = farmLib.poolInfo(_pid);
        (, , , , , , , , , pool.accLpPerShare, pool.accLpTwoPerShare, pool.accLpThrPerShare) = farmLib.poolLpInfo(_pid);
        UserLpInfo storage userLp = userLpInfo[_pid][_msgSender()];
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            uint256 _extraAmount = _amount.mul(_selfGain.add(_parentGain)).div(100);
            farmLib.setExtraAmount(_pid, pool.extraAmount.sub(_extraAmount));
            farmLib.setLpSupply(_pid, pool.lpSupply.sub(_amount));
            pool.lpToken.safeTransfer(_msgSender(), _amount);
        }
        uint256 _amountGain = user.amount.add(user.amount.mul(_selfGain.add(_parentGain)).div(100));
        user.rewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e22);
        userLp.lpRewardDebt = _amountGain.mul(pool.accLpPerShare).div(1e22);
        userLp.lpTwoRewardDebt = _amountGain.mul(pool.accLpTwoPerShare).div(1e22);
        userLp.lpThrRewardDebt = _amountGain.mul(pool.accLpThrPerShare).div(1e22);
    }

    // Stake Star NFT to MasterChef
    function enterStakingNFT(uint256 _tokenId) external {
        require(isDeposit == true, "Not started");
        address _user = _msgSender();
        PoolInfo memory pool;
        UserInfo storage user = userInfo[0][_user];
        UserLpInfo storage userLp = userLpInfo[0][_user];
        require(starNFT.ownerOf(_tokenId) == _user, "error");
        farmLib.updatePool(0);
        farmLib.harvest(0, _user, 0, true);
        farmLib.harvestLp(0, _user, true);
        (, , pool.lpSupply, , , pool.accStarPerShare, pool.extraAmount, , pool.size, , ,) = farmLib.poolInfo(0);
        (, , , , , , , , , pool.accLpPerShare, pool.accLpTwoPerShare, pool.accLpThrPerShare) = farmLib.poolLpInfo(0);
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_user);
        if (_tokenId > 0) {
            starNFT.transferFrom(_user, address(this), _tokenId);
            (uint256 level, , uint256 _price, uint256 _multi) = nftLogic.starMeta(_tokenId);
            userNFTs[_user].push(_tokenId);
            StakingNFTs.push(_tokenId);
            StakingIndex[_tokenId] = StakingNFTs.length - 1;
            NFTGroup[level].push(_tokenId);
            groupIndex[level][_tokenId] = NFTGroup[level].length - 1;
            nftUser[_tokenId] = _user;
            uint256 _amount = _price.mul(_multi).div(100);
            uint256 _extraAmount = _amount.mul(_selfGain.add(_parentGain)).div(100);
            farmLib.setExtraAmount(0, pool.extraAmount.add(_extraAmount));
            farmLib.setLpSupply(0, pool.lpSupply.add(_amount));
            user.nftAmount = user.nftAmount.add(_amount);
            user.nftLastDeposit = block.timestamp;
            if(isPoolUser[0][_user] == false){
                userIndex[0][pool.size] = _user;
                farmLib.setSize(0, pool.size.add(1));
                isPoolUser[0][_user] = true;
            }
        }
        uint256 _amountGain = user.nftAmount.add(user.nftAmount.mul(_selfGain.add(_parentGain)).div(100));
        user.nftRewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e22);
        userLp.lpRewardDebt = _amountGain.mul(pool.accLpPerShare).div(1e22);
        userLp.lpTwoRewardDebt = _amountGain.mul(pool.accLpTwoPerShare).div(1e22);
        userLp.lpThrRewardDebt = _amountGain.mul(pool.accLpThrPerShare).div(1e22);
        emit Deposit(_user, 0, _tokenId, isNodeUser[_user]);
    }

    // Withdraw Star NFT from STAKING.
    function leaveStakingNFT(uint256 _tokenId) public {
        PoolInfo memory pool;
        UserInfo storage user = userInfo[0][_msgSender()];
        UserLpInfo storage userLp = userLpInfo[0][_msgSender()];
        SlotInfo memory slot;
        require(userNFTs[_msgSender()].length > 0, "no NFT");
        farmLib.updatePool(0);
        (slot._selfGain, slot._parentGain) = starNode.nodeGain(_msgSender());
        slot._self_parentGain = slot._selfGain.add(slot._parentGain);
        uint256 _amount;
        if (_tokenId > 0) {
            require(nftUser[_tokenId] == _msgSender(), "error");
            (, , uint256 _price, uint256 _multi) = nftLogic.starMeta(_tokenId);
            _amount = _price.mul(_multi).div(100);
        }
        farmLib.harvest(0, _msgSender(), _amount, true);
        farmLib.harvestLp(0, _msgSender(), true);
        (, , pool.lpSupply, , , pool.accStarPerShare, pool.extraAmount, , pool.size, , ,) = farmLib.poolInfo(0);
        (, , , , , , , , , pool.accLpPerShare, pool.accLpTwoPerShare, pool.accLpThrPerShare) = farmLib.poolLpInfo(0);
        if (_tokenId > 0) {
            uint256[] storage _userNFTs = userNFTs[_msgSender()];
            for (uint256 i = 0; i < _userNFTs.length; i++) {
                if(_userNFTs[i] == _tokenId) {
                    if(_amount > 0) {
                        (uint256 level, , ,) = nftLogic.starMeta(_tokenId);
                        uint256 _extraAmount = _amount.mul(slot._self_parentGain).div(100);
                        farmLib.setExtraAmount(0, pool.extraAmount.sub(_extraAmount));
                        farmLib.setLpSupply(0, pool.lpSupply.sub(_amount));
                        user.nftAmount = user.nftAmount.sub(_amount);
                        slot._userNFTsIndex = _userNFTs.length - 1;
                        _userNFTs[i] = _userNFTs[slot._userNFTsIndex];
                        _userNFTs.pop();
                        uint256 indexd = StakingIndex[_tokenId];
                        slot.StakingNFTsIndex = StakingNFTs.length - 1;
                        StakingNFTs[indexd] = StakingNFTs[slot.StakingNFTsIndex];
                        StakingIndex[StakingNFTs[indexd]] = indexd;
                        StakingIndex[_tokenId] = 0;
                        StakingNFTs.pop();
                        uint256 groupIndexd = groupIndex[level][_tokenId];
                        slot.NFTGroupIndex = NFTGroup[level].length - 1;
                        NFTGroup[level][groupIndexd] = NFTGroup[level][slot.NFTGroupIndex];
                        groupIndex[level][NFTGroup[level][groupIndexd]] = groupIndexd;
                        groupIndex[level][_tokenId] = 0;
                        NFTGroup[level].pop();
                        nftUser[_tokenId] = address(0);
                    }
                    starNFT.transferFrom(address(this), _msgSender(), _tokenId);
                    break;
                }
            }
        }
        uint256 _amountGain = user.nftAmount.add(user.nftAmount.mul(slot._self_parentGain).div(100));
        user.nftRewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e22);
        userLp.nftLpRewardDebt = _amountGain.mul(pool.accLpPerShare).div(1e22);
        userLp.nftLpTwoRewardDebt = _amountGain.mul(pool.accLpTwoPerShare).div(1e22);
        userLp.nftLpThrRewardDebt = _amountGain.mul(pool.accLpThrPerShare).div(1e22);
    }

    // Called when joining the base
    function regNodeUser(address _user) external onlyNode {
        require(address(0) != _user);
        PoolInfo memory pool;
        SlotInfo memory slot;
        for(uint256 i = 0; i < farmLib.poolLength(); i++){
            (, , , , , pool.accStarPerShare, pool.extraAmount, , , , , ) = farmLib.poolInfo(i);
            (, , , , , , , , , pool.accLpPerShare, pool.accLpTwoPerShare, pool.accLpThrPerShare) = farmLib.poolLpInfo(i);
	    	UserInfo storage user = userInfo[i][_user];
	    	UserLpInfo storage userLp = userLpInfo[i][_user];
            farmLib.updatePool(i);
            uint256 _amount = user.amount.add(user.nftAmount);
            if(_amount > 0) {
                (slot._selfGain, slot._parentGain) = starNode.nodeGain(_user);
                uint256 _extraAmount = _amount.mul(slot._selfGain.add(slot._parentGain)).div(100);
                farmLib.setExtraAmount(i, pool.extraAmount.add(_extraAmount));
                slot._amountGain = user.amount.add(user.amount.mul(slot._selfGain.add(slot._parentGain)).div(100));
                uint256 pending = user.amount.mul(pool.accStarPerShare).div(1e22).sub(user.rewardDebt);
                user.rewardDebt = slot._amountGain.mul(pool.accStarPerShare).div(1e22).sub(pending);
                uint256 lpPending = user.amount.mul(pool.accLpPerShare).div(1e22).sub(userLp.lpRewardDebt);
                userLp.lpRewardDebt = slot._amountGain.mul(pool.accLpPerShare).div(1e22).sub(lpPending);
                if(i == 0){
                    uint256 _nftAmountGain = user.nftAmount.add(user.nftAmount.mul(slot._selfGain.add(slot._parentGain)).div(100));
                    uint256 nftpending = user.nftAmount.mul(pool.accStarPerShare).div(1e22).sub(user.nftRewardDebt);
                    user.nftRewardDebt = _nftAmountGain.mul(pool.accStarPerShare).div(1e22).sub(nftpending);
                }
            }
        }
        isNodeUser[_user] = true;
    }

    function setIsNotLp(uint256 _pid, bool _isNotLp) external onlyOwner {
        isNotLp[_pid] = _isNotLp;
    }

    function setPoolUser(uint256 _pid, address _user) external onlyFarmLib {
        isPoolUser[_pid][_user] = true;
    }

    function setUserIndex(uint256 _pid, uint256 _size, address _user) external onlyFarmLib {
        userIndex[_pid][_size] = _user;
    }

    // Get Specify the level length
    function getNFTGroupAmount(uint256 _level) view external returns(uint256) {
        return NFTGroup[_level].length;
    }

    //Get the pledge length of the specified user nft
    function getUserStakingNFTAmount(address _user) view external returns (uint256) {
        return userNFTs[_user].length;
    }

    // Get nft pledge length
    function getStakingNFTAmount() view external returns (uint256) {
        return StakingNFTs.length;
    }

    // Get the specified user userNFTs
    function getUserNFTs(address _user) view external returns(uint256[] memory){
        return userNFTs[_user];
    }
	
    // Set starNode address
    function setNode(address _node) external onlyOwner {
        require(address(0) != _node);
        starNode = IStarNode(_node);
    }

    function setFarmLib(address _addr) public onlyOwner {
        require(address(0) != _addr, "farmLib empty");
        farmLib = IFarmLib(_addr);
    }

    // Set StarNFT address
    function setStarNFT(address _addr) external onlyOwner {
        require(address(0) != _addr, "address is 0");
        starNFT = IERC721(_addr);
    }

    // Set nftLogic address
    function setNFTLogic(address _addr) external onlyOwner {
        require(address(0) != _addr);
        nftLogic = INFTLogic(_addr);
    }

    // Set Airdrop address
    function setAirdrop(address _addr) external onlyOwner {
        require(address(0) != _addr);
        Airdrop = IAirdrop(_addr);
    }

    modifier onlyNode() {
        require(_msgSender() == address(starNode), "not node");
        _;
    }

    modifier onlyFarmLib() {
        require(_msgSender() == address(farmLib), "not farmLib");
        _;
    }

    receive() external payable{
        emit Received(_msgSender(), msg.value);
    }
}