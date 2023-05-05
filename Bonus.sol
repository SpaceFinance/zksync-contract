// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Owned.sol";

interface IStarNFT {
    function balanceOf(address owner) view external returns (uint256);
    function tokenOfOwnerByIndex(address owner,uint256 tokenid) view external returns (uint256);
}

interface INFTLogic {
    function setBonusToke(uint256 _tokenId,uint256 _amountBonus) external;
    function disposeBonusToke(uint256 _tokenId) view external returns (uint256);
    function setXBonusToke(uint256 _tokenId,uint256 _amountBonus) external;           
    function disposeXBonusToke(uint256 _tokenId) view external returns (uint256);     
    function getXSpaceNFTStatus(uint256 _tokenId) view external returns(bool);       

    function getAllTokenId() view external returns (uint256[] memory);  
    function getStarMeta(uint256 _tokenId) view external returns (uint256,uint256);
    function totalPrice() view external returns (uint256); 
}

interface INFTMarket {
    function getUserTokensLength(address _user) view external returns (uint256);
    function getUserTokens(address _user) view external returns (uint256[] memory);
}

interface IStarFarm {
    function getUserStakingNFTAmount(address _user) view external returns (uint256);
    function getUserNFTs(address _user) view external returns (uint256[] memory);
}

interface IBonus {
    function tokenWithdraw(uint256 _tokenId) view external returns (uint256);
    function XtokenWithdraw(uint256 _tokenId) view external returns (uint256);
}


contract Bonus is owned {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IERC20 public starToken;
    IERC20 public XstarToken;  
    IERC721 public starNFT;
    INFTLogic public NFTLogic;
    INFTMarket public NFTMarket;
    IStarFarm public StarFarm;
    IStarNFT public StarNFTInterface;
    address public farmLib;
    address public lockAddr;
    address public StarCrossChain;
    address public nodeAddr;
    uint256 public lockRatio;
    uint256 public bonusWithdrawn;
    uint256 public lockWithdrawn;
    uint256 public totalAmount;
    uint256 public XtotalAmount;      
    uint256 public XbonusWithdrawn;   
    mapping(uint256 => uint256) public tokenWithdraw;
    mapping(uint256 => uint256) public XtokenWithdraw;  

    constructor(address _starToken, address _lock, uint256 _lockRatio) {
        require(_lockRatio < 100, "ratio error");
        starToken = IERC20(_starToken);
        lockAddr = _lock;
        lockRatio = _lockRatio;
    }

    function setLockRatio(uint256 _newRatio) onlyOwner public {
        require(_newRatio < 100, "ratio error");
        lockRatio = _newRatio;
    }

    function lockWithdraw(uint256 _amount) onlyLockUser public {
        require(_amount > 0, "amount error");
        uint256 _balance = starToken.balanceOf(address(this));
        uint256 _availLock = _balance.add(lockWithdrawn).add(bonusWithdrawn).mul(lockRatio).div(100).sub(lockWithdrawn);
        require(_amount <= _availLock, "amount error");
        lockWithdrawn = lockWithdrawn.add(_amount);
        starToken.safeTransfer(_msgSender(), _amount);
    }

    function _getBonus(uint256 _tokenId) internal view returns (uint256) {
        uint256 bonunsAmount = NFTLogic.disposeBonusToke(_tokenId);
        return bonunsAmount;
    }

    function _getXBonus(uint256 _tokenId) internal view returns (uint256) {
        uint256 bonunsAmount = NFTLogic.disposeXBonusToke(_tokenId);
        return bonunsAmount;
    }

    function getTokenWithdraw(uint256 _tokenId) public view returns(uint256){
        return tokenWithdraw[_tokenId];
    }

    function allWithdrawal(address owner) public{
        owner = _msgSender();
        uint256 _amount = 0;
        uint256 _Xamount = 0;
        for (uint256 i = 0 ; i < StarNFTInterface.balanceOf(owner); i ++){
            uint256 _tokenId = StarNFTInterface.tokenOfOwnerByIndex(owner,i);
            uint256 _xSpaceNumber = _getXBonus(_tokenId);
            XtokenWithdraw[_tokenId] = XtokenWithdraw[_tokenId].add(_xSpaceNumber);
            NFTLogic.setXBonusToke(_tokenId,0);
            _Xamount = _Xamount.add(_xSpaceNumber);
            uint256 _SpaceNumber = _getBonus(_tokenId);
            tokenWithdraw[_tokenId] = tokenWithdraw[_tokenId].add(_SpaceNumber);
            NFTLogic.setBonusToke(_tokenId,0);
            _amount = _amount.add(_SpaceNumber);
        }
        for (uint256 i = 0 ; i < NFTMarket.getUserTokensLength(owner); i ++){
            uint256[] memory _tokenIds = NFTMarket.getUserTokens(owner);
            for (uint256 j = 0 ; j < _tokenIds.length; j ++){
                uint256 _tokenId = _tokenIds[j];
                uint256 _xSpaceNumber = _getXBonus(_tokenIds[j]);
                XtokenWithdraw[_tokenId] = XtokenWithdraw[_tokenId].add(_xSpaceNumber);
                NFTLogic.setXBonusToke(_tokenIds[j],0);
                _Xamount = _Xamount.add(_xSpaceNumber);
                uint256 _SpaceNumber = _getBonus(_tokenIds[j]);
                tokenWithdraw[_tokenId] = tokenWithdraw[_tokenId].add(_SpaceNumber);
                NFTLogic.setBonusToke(_tokenIds[j],0);
                _amount = _amount.add(_SpaceNumber);
            }
        }
        for (uint256 i = 0 ; i < StarFarm.getUserStakingNFTAmount(owner); i ++){
            uint256[] memory _tokenIds = StarFarm.getUserNFTs(owner);
            for (uint256 j = 0 ; j < _tokenIds.length; j ++){
                uint256 _tokenId = _tokenIds[j];
                uint256 _xSpaceNumber = _getXBonus(_tokenId);
                XtokenWithdraw[_tokenId] = XtokenWithdraw[_tokenId].add(_xSpaceNumber);
                NFTLogic.setXBonusToke(_tokenId,0);
                _Xamount = _Xamount.add(_xSpaceNumber);
                uint256 _SpaceNumber = _getBonus(_tokenId);
                tokenWithdraw[_tokenId] = tokenWithdraw[_tokenId].add(_SpaceNumber);
                NFTLogic.setBonusToke(_tokenId,0);
                _amount = _amount.add(_SpaceNumber);
            }
        }
        bonusWithdrawn = bonusWithdrawn.add(_amount);
        XbonusWithdrawn = XbonusWithdrawn.add(_Xamount);
        if(_amount != 0){
            starToken.safeTransfer(_msgSender(), _amount);
        }
        if(_Xamount != 0){
            XstarToken.safeTransfer(_msgSender(), _Xamount);
        }
    }

    function transferLogic(address _owner,uint256 _amount) external onlyLogic {
        starToken.safeTransfer(_owner, _amount);
    }

    function XtransferLogic(address _owner,uint256 _amount) external onlyLogic {
        XstarToken.safeTransfer(_owner, _amount);
    }

    modifier onlyLogic() {
        require(INFTLogic(_msgSender()) == NFTLogic, "no permission");
        _;
    }

    function transferMarket(address _owner,uint256 _amount) external onlyMarket {
        starToken.safeTransfer(_owner, _amount);
    }

    function XtransferMarket(address _owner,uint256 _amount) external onlyMarket {
        XstarToken.safeTransfer(_owner, _amount);
    }

    function addTotalAmount(uint256 _amount) external onlyPower {
        totalAmount = totalAmount.add(_amount);
    }

    function addXTotalAmount(uint256 _amount) external onlyPower {
        XtotalAmount = XtotalAmount.add(_amount);
    }

    function getXTotalAmount() external view returns (uint256) {
        return XtotalAmount;
    }
    
    function getTotalAmount() external view returns (uint256) {
        return totalAmount;
    }

    function getlockRatio() external view returns (uint256) {
        return lockRatio;
    }

    function getlockAddress() external view returns (address) {
        return lockAddr;
    }

    function setTokenWithdraw(uint256 _tokenId,uint256 _amount) external onlyPower {
        tokenWithdraw[_tokenId] = tokenWithdraw[_tokenId].add(_amount);
    }

    function setBonusWithdrawn(uint256 _amount) external onlyPower {
        bonusWithdrawn = bonusWithdrawn.add(_amount);
    }

    function getBonus(uint256 _tokenId) view external returns (uint256) {
        return _getBonus(_tokenId);
    }

    function getXBonus(uint256 _tokenId) view external returns (uint256) {
        return _getXBonus(_tokenId);
    }

    function setNode(address _node) onlyOwner public {
        require(address(0) != _node, "node address error");
        nodeAddr = _node;
    }

    function setLock(address _addr) onlyOwner public {
        require(address(0) != _addr, "lock address error");
        lockAddr = _addr;
    }

    function setNFT(address _addr) onlyOwner public {
        require(address(0) != _addr, "NFT address error");
        starNFT = IERC721(_addr);
        StarNFTInterface = IStarNFT(_addr);
    }

    function setNFTLogic(address _addr) onlyOwner public {
        require(address(0) != _addr, "NFTLogic address error");
        NFTLogic = INFTLogic(_addr);
    }

    function setNFTMarket(address _addr) onlyOwner public {
        require(address(0) != _addr, "NFTMarket address error");
        NFTMarket = INFTMarket(_addr);
    }

    function setStarFarm(address _addr) onlyOwner public {
        require(address(0) != _addr, "StarFarm address error");
        StarFarm = IStarFarm(_addr);
    }

    function setFarmLib(address _addr) onlyOwner public {
        require(address(0) != _addr, "farmLib address error");
        farmLib = _addr;
    }

    function setXstarToken(address _addr) onlyOwner public {
        require(address(0) != _addr, "XstarToken address error");
        XstarToken = IERC20(_addr);
    }

    function setStarCrossChain(address _addr) onlyOwner public {
        require(address(0) != _addr, "StarCrossChain address error");
        StarCrossChain = _addr;
    }

    modifier onlyLockUser() {
        require(_msgSender() == lockAddr, "no permission");
        _;
    }

    modifier onlyMarket() {
        require(INFTMarket(_msgSender()) == NFTMarket, "no permission");
        _;
    }
    
    modifier onlyPower() {
        require(_msgSender() == StarCrossChain || _msgSender() == owner || _msgSender() == nodeAddr || _msgSender() == farmLib || INFTLogic(_msgSender()) == NFTLogic || INFTMarket(_msgSender()) == NFTMarket , "no permission");
        _;
    }
}