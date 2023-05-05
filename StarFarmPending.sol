// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Owned.sol";

interface IStarNode {
    function nodeGain(address _user) external view returns (uint256, uint256);
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
    function isPoolUser(uint256 _pid, address _user) external view returns (bool);
    function isNodeUser(address _user) external view returns (bool);
    function setPoolUser(uint256 _pid, address _user) external;
    function setUserIndex(uint256 _pid, uint256 _size, address _user) external;
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
    function alloc() external view returns(
        address lockAddr,
        address teamAddr,
        address rewardAddr,
        uint256 lockRatio,
        uint256 teamRatio,
        uint256 rewardRatio
    );

    function getMultiplier(uint256 _from, uint256 _to) external view returns (uint256);
    function starPerBlock() external view returns(uint256);
    function totalAllocPoint() external view returns(uint256);
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

interface INFTLogic {
    function starMeta(uint256 _tokenId) view external returns (uint8, uint256, uint256, uint256);
}

contract FarmPending is owned {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct SlotInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastDeposit;
        uint256 nftAmount;
        uint256 nftRewardDebt;
        uint256 nftLastDeposit;
        uint256 lpRewardDebt;
        uint256 lpTwoRewardDebt;
        uint256 lpThrRewardDebt;
        uint256 nftLpRewardDebt;
        uint256 nftLpTwoRewardDebt;
        uint256 nftLpThrRewardDebt;
        uint256 lpSupply;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accStarPerShare;
        uint256 extraAmount;
        uint256 deflationRate;
        uint256 xRate;
        uint256 bond;
        uint256 lpPerBlock;
        uint256 lpTwoPerBlock;
        uint256 lpThrPerBlock;
        uint256 accLpPerShare;
        uint256 accLpTwoPerShare;
        uint256 accLpThrPerShare;
        uint256 multiplier;
        uint256 starReward;
        uint256 _amount;
        uint256 _amountGain;
        uint256 allNFTPendingStar;
        uint256 allNFTLpPendingStar;
        uint256 allNFTLpTwoPendingStar;
        uint256 allNFTLpThrPendingStar;
        uint256 _selfGain;
        uint256 _parentGain;
        uint256 _self_parentGain;
        uint256 lockRatio;
        uint256 teamRatio;
        uint256 rewardRatio;
    }

    IStarNode public starNode;
    IFarmLib public farmLib;
    IMasterChef public starFarm;
    INFTLogic public nftLogic;

    constructor(address _node, address _farmLib, address _starFarm) {
        starNode = IStarNode(_node);
        farmLib = IFarmLib(_farmLib);
        starFarm = IMasterChef(_starFarm);
    }

    // View function to see pending STARs on frontend.
    function pendingStar(uint256 _pid, address _user) external view returns (uint256 _amountpendingStar, uint256 _amountLpPendingStar, uint256 _amountLpTwoPendingStar, uint256 _amountLpThrPendingStar) {
        SlotInfo memory slot;
        (, , slot.lpSupply, slot.allocPoint, slot.lastRewardBlock, slot.accStarPerShare, slot.extraAmount, , , , , ) = farmLib.poolInfo(_pid);
        (, , , , , , slot.lpPerBlock, slot.lpTwoPerBlock, slot.lpThrPerBlock, slot.accLpPerShare, slot.accLpTwoPerShare, slot.accLpThrPerShare) = farmLib.poolLpInfo(_pid);
        (, , , slot.lockRatio, slot.teamRatio, slot.rewardRatio) = farmLib.alloc();
        (slot.amount, slot.rewardDebt, , , , ) = starFarm.userInfo(_pid, _user);
        (slot.lpRewardDebt, slot.lpTwoRewardDebt, slot.lpThrRewardDebt, , , ) = starFarm.userLpInfo(_pid, _user);
        if (slot.amount > 0) {
            slot.multiplier = farmLib.getMultiplier(slot.lastRewardBlock, block.timestamp);
            slot.starReward = slot.multiplier.mul(farmLib.starPerBlock()).mul(slot.allocPoint).div(farmLib.totalAllocPoint());
            slot.lpSupply = slot.lpSupply.add(slot.extraAmount);
            slot.accStarPerShare = slot.accStarPerShare.add(slot.starReward.mul(1e22).div(slot.lpSupply));
            slot.accLpPerShare = slot.accLpPerShare.add(slot.multiplier.mul(slot.lpPerBlock).mul(1e22).div(slot.lpSupply));
            slot.accLpTwoPerShare = slot.accLpTwoPerShare.add(slot.multiplier.mul(slot.lpTwoPerBlock).mul(1e22).div(slot.lpSupply));
            slot.accLpThrPerShare = slot.accLpThrPerShare.add(slot.multiplier.mul(slot.lpThrPerBlock).mul(1e22).div(slot.lpSupply));
            (slot._selfGain, slot._parentGain) = starNode.nodeGain(_user);
            slot._amountGain = slot.amount.add(slot.amount.mul(slot._selfGain.add(slot._parentGain)).div(100));
            _amountpendingStar = slot._amountGain.mul(slot.accStarPerShare).div(1e22).sub(slot.rewardDebt);
            _amountLpPendingStar = slot._amountGain.mul(slot.accLpPerShare).div(1e22).sub(slot.lpRewardDebt);
            _amountLpTwoPendingStar = slot._amountGain.mul(slot.accLpTwoPerShare).div(1e22).sub(slot.lpTwoRewardDebt);
            _amountLpThrPendingStar = slot._amountGain.mul(slot.accLpThrPerShare).div(1e22).sub(slot.lpThrRewardDebt);
            if(_amountpendingStar > 0) {
                _amountpendingStar = _amountpendingStar.sub(_amountpendingStar.mul(slot.lockRatio.add(slot.teamRatio)).div(10000));
                _amountpendingStar = _amountpendingStar.sub(_amountpendingStar.mul(slot.rewardRatio).div(10000));
                _amountpendingStar = _amountpendingStar.mul(100).div(slot._selfGain.add(slot._parentGain).add(100));
            }
            if(_amountLpPendingStar > 0) {
                _amountLpPendingStar = _amountLpPendingStar.mul(100).div(slot._selfGain.add(slot._parentGain).add(100));
            }
            if(_amountLpTwoPendingStar > 0) {
                _amountLpTwoPendingStar = _amountLpTwoPendingStar.mul(100).div(slot._selfGain.add(slot._parentGain).add(100));
            }
            if(_amountLpThrPendingStar > 0) {
                _amountLpThrPendingStar = _amountLpThrPendingStar.mul(100).div(slot._selfGain.add(slot._parentGain).add(100));
            }
        }
    }

    //View function to see pending STARs on frontend of nft.
    function nftPendingStar(address _user, uint256 _tokenId) external view returns (uint256 _amountpendingStar, uint256 _amountLpPendingStar, uint256 _amountLpTwoPendingStar, uint256 _amountLpThrPendingStar) {
        SlotInfo memory slot;
        (, , slot.lpSupply, slot.allocPoint, slot.lastRewardBlock, slot.accStarPerShare, slot.extraAmount, , , , ,) = farmLib.poolInfo(0);
        (, , , , , , slot.lpPerBlock, slot.lpTwoPerBlock, slot.lpThrPerBlock, slot.accLpPerShare, slot.accLpTwoPerShare, slot.accLpThrPerShare) = farmLib.poolLpInfo(0);
        (, , , slot.lockRatio, slot.teamRatio, slot.rewardRatio) = farmLib.alloc();
        (, , , slot.nftAmount, slot.nftRewardDebt, ) = starFarm.userInfo(0, _user);
        (slot.lpRewardDebt, slot.lpTwoRewardDebt, slot.lpThrRewardDebt, slot.nftLpRewardDebt, slot.nftLpTwoRewardDebt, slot.nftLpThrRewardDebt) = starFarm.userLpInfo(0, _user);
        slot.lpSupply = slot.lpSupply.add(slot.extraAmount);
        if (slot.nftAmount > 0) {
            slot.multiplier = farmLib.getMultiplier(slot.lastRewardBlock, block.timestamp);
            slot.starReward = slot.multiplier.mul(farmLib.starPerBlock()).mul(slot.allocPoint).div(farmLib.totalAllocPoint());
            slot.accStarPerShare = slot.accStarPerShare.add(slot.starReward.mul(1e22).div(slot.lpSupply));
            slot.accLpPerShare = slot.accLpPerShare.add(slot.lpPerBlock.mul(1e22).div(slot.lpSupply));
            slot.accLpTwoPerShare = slot.accLpTwoPerShare.add(slot.lpTwoPerBlock.mul(1e22).div(slot.lpSupply));
            slot.accLpThrPerShare = slot.accLpThrPerShare.add(slot.lpThrPerBlock.mul(1e22).div(slot.lpSupply));
            (slot._selfGain, slot._parentGain) = starNode.nodeGain(_user);
            (, , uint256 _price, uint256 _multi) = nftLogic.starMeta(_tokenId);
            slot._amount = _price.mul(_multi).div(100);
            slot._amountGain = slot._amount.add(slot._amount.mul(slot._selfGain.add(slot._parentGain)).div(100));
            slot.nftAmount = slot.nftAmount.add(slot.nftAmount.mul(slot._selfGain.add(slot._parentGain)).div(100));
            slot.allNFTPendingStar = slot.nftAmount.mul(slot.accStarPerShare).div(1e22).sub(slot.nftRewardDebt);
            slot.allNFTLpPendingStar = slot.nftAmount.mul(slot.accLpPerShare).div(1e22).sub(slot.nftLpRewardDebt);
            slot.allNFTLpTwoPendingStar = slot.nftAmount.mul(slot.accLpTwoPerShare).div(1e22).sub(slot.nftLpTwoRewardDebt);
            slot.allNFTLpThrPendingStar = slot.nftAmount.mul(slot.accLpThrPerShare).div(1e22).sub(slot.nftLpThrRewardDebt);
            _amountpendingStar = slot.allNFTPendingStar.mul(slot._amountGain).div(slot.nftAmount);
            _amountLpPendingStar = slot.allNFTLpPendingStar.mul(slot._amountGain).div(slot.nftAmount);
            _amountLpTwoPendingStar = slot.allNFTLpTwoPendingStar.mul(slot._amountGain).div(slot.nftAmount);
            _amountLpThrPendingStar = slot.allNFTLpThrPendingStar.mul(slot._amountGain).div(slot.nftAmount);
            if(_amountpendingStar > 0) {
                _amountpendingStar = _amountpendingStar.sub(_amountpendingStar.mul(slot.lockRatio.add(slot.teamRatio)).div(10000));
                _amountpendingStar = _amountpendingStar.sub(_amountpendingStar.mul(slot.rewardRatio).div(10000));
                _amountpendingStar = _amountpendingStar.mul(100).div(slot._selfGain.add(slot._parentGain).add(100));
            }
            if(_amountLpPendingStar > 0) {
                _amountLpPendingStar = _amountLpPendingStar.mul(100).div(slot._selfGain.add(slot._parentGain).add(100));
            }
            if(_amountLpTwoPendingStar > 0) {
                _amountLpTwoPendingStar = _amountLpTwoPendingStar.mul(100).div(slot._selfGain.add(slot._parentGain).add(100));
            }
            if(_amountLpThrPendingStar > 0) {
                _amountLpThrPendingStar = _amountLpThrPendingStar.mul(100).div(slot._selfGain.add(slot._parentGain).add(100));
            }
        }
    }

    function setNode(address _node) external onlyOwner {
        require(address(0) != _node);
        starNode = IStarNode(_node);
    }

    function setStarFarm(address _addr) public onlyOwner{
        require(address(0) != _addr);
        starFarm = IMasterChef(_addr);
    }

    function setFarmLib(address _addr) public onlyOwner {
        require(address(0) != _addr, "farmLib empty");
        farmLib = IFarmLib(_addr);
    }

    function setNFTLogic(address _addr) external onlyOwner {
        require(address(0) != _addr);
        nftLogic = INFTLogic(_addr);
    }
}