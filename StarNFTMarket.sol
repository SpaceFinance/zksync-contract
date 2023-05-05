// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Owned.sol";

interface IBonus {
    function getBonus(uint256 _tokenId) view external returns (uint256);
    function getlockRatio() view external returns (uint256);
    function getlockAddress() view external returns (address);
    function transferMarket(address _owner,uint256 _amount) external;
    function addTotalAmount(uint256) external;
    function getXBonus(uint256 _tokenId) view external returns (uint256);       
    function addXTotalAmount(uint256) external;         
    function XtransferMarket(address _owner,uint256 _amount) external;     
}

interface INFTLogic {
    function setBonusToke(uint256 _tokenId,uint256 _amountBonus) external;
    function starMeta(uint256 _tokenId) view external returns (uint8, uint256, uint256, uint256);
    function setXBonusToke(uint256 _tokenId,uint256 _amountBonus) external;     
}

contract NFTMarket is owned, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IERC20 public starToken;
    IERC721 public starNFT;
    address public bonusAddr;
    uint256 public fee;
    IBonus private Bonus;
    INFTLogic public NFTLogic;

    struct TokenInfo {
        address owner;
        uint256 price;
    }

    // tokenId => price
    mapping (uint256 => TokenInfo) public tokenInfo;
    uint256[] public marketTokens;
    // tokenid => marketToken Index
    mapping(uint256 => uint256) public tokensIndex;
    mapping(address => uint256) public UserTotalWithdrawalBonus;
    mapping(address => uint256[]) public userTokens;
    mapping(address => mapping(uint256 => uint256)) public userTokensIndex;
    mapping(address => uint256) public userStar;
    mapping(uint256 => uint256[]) public groupTokens;
    mapping(uint256 => mapping(uint256 => uint256)) public groupIndex;
    mapping(address => uint256) public XUserTotalWithdrawalBonus;    

    constructor(address _starToken,  address _bonus, address _starNFT, uint256 _fee) {
        starToken = IERC20(_starToken);
        starNFT = IERC721(_starNFT);
        bonusAddr = _bonus;
        Bonus = IBonus(bonusAddr);
        fee = _fee;
    }

    function _addToken(address _user, uint256 _tokenId) private {
        marketTokens.push(_tokenId);
        tokensIndex[_tokenId] = marketTokens.length - 1;
        userTokens[_user].push(_tokenId);
        userTokensIndex[_user][_tokenId] = userTokens[_msgSender()].length - 1;
        (uint256 level, , , ) = NFTLogic.starMeta(_tokenId);
        groupTokens[level].push(_tokenId);
        groupIndex[level][_tokenId] = groupTokens[level].length - 1;
    }

    function _removeToken(address _user, uint256 _tokenId) private {
        uint256 tokenIndex = tokensIndex[_tokenId];
        uint256 lastTokenId = marketTokens[marketTokens.length - 1];
        marketTokens[tokenIndex] = lastTokenId;
        tokensIndex[lastTokenId] = tokenIndex;
        delete tokensIndex[_tokenId];
        marketTokens.pop();
        uint256 userTokenIndex = userTokensIndex[_user][_tokenId];
        uint256 userLastTokenId = userTokens[_user][userTokens[_user].length - 1];
        userTokens[_user][userTokenIndex] = userLastTokenId;
        userTokensIndex[_user][userLastTokenId] = userTokenIndex;
        delete userTokensIndex[_user][_tokenId];
        userTokens[_user].pop();
        (uint256 level, , , ) = NFTLogic.starMeta(_tokenId);
        uint256 groupIndexd = groupIndex[level][_tokenId];
        groupTokens[level][groupIndexd] = groupTokens[level][groupTokens[level].length - 1];
        groupIndex[level][groupTokens[level][groupIndexd]] = groupIndexd;
        groupIndex[level][_tokenId] = 0;
        groupTokens[level].pop();
    }

    function getGroupTokensLength(uint256 _level) view public returns (uint256) {
        return groupTokens[_level].length;
    }

    function getMarketTokensLength() view public returns (uint256) {
        return marketTokens.length;
    }

    function getUserTokensLength(address _user) view public returns (uint256) {
        return userTokens[_user].length;
    }

    function setTokenSale(uint256 _tokenId, bool _sale, uint256 _price) public {
        if (_sale) {
            require(starNFT.ownerOf(_tokenId) == _msgSender(), "not your token");
            require(_price > 0, "price not allow 0");
            _addToken(_msgSender(), _tokenId);
            tokenInfo[_tokenId].owner = _msgSender();
            tokenInfo[_tokenId].price = _price;
            starNFT.transferFrom(_msgSender(), address(this), _tokenId);
        } else {
            require(tokenInfo[_tokenId].owner == _msgSender(), "not your token");
            _removeToken(_msgSender(), _tokenId);
            tokenInfo[_tokenId].owner = address(0);
            tokenInfo[_tokenId].price = 0;
            starNFT.transferFrom(address(this), _msgSender(), _tokenId);
        }
    }

    function purchaseToken(uint256 _tokenId) public nonReentrant {
        require(_msgSender() != address(0), "msgSender address can not be address 0");
        require(tokenInfo[_tokenId].owner != address(0), "not sale");
        // add fee
        uint256 _price = tokenInfo[_tokenId].price;
        starToken.transferFrom(_msgSender(), address(this), _price);
        uint256 _fee = _price.mul(fee).div(100);
        uint256 lockRatio =Bonus.getlockRatio();
        uint256 amountBonus = _fee.mul(100 - lockRatio).div(100);
        starToken.safeTransfer(Bonus.getlockAddress(), _fee.mul(lockRatio).div(100));
        starToken.safeTransfer(bonusAddr, amountBonus);
        Bonus.addTotalAmount(amountBonus);
        userStar[tokenInfo[_tokenId].owner] = userStar[tokenInfo[_tokenId].owner].add(_price.sub(_fee));
        starToken.safeTransfer(tokenInfo[_tokenId].owner, _price.sub(_fee));
        starNFT.transferFrom(address(this), _msgSender(), _tokenId);
        _removeToken(tokenInfo[_tokenId].owner, _tokenId);
        uint256 _amountXBonus = Bonus.getXBonus(_tokenId);
        if(_amountXBonus > 0 && tokenInfo[_tokenId].owner != _msgSender()){
            XUserTotalWithdrawalBonus[tokenInfo[_tokenId].owner] += _amountXBonus;
            Bonus.XtransferMarket(tokenInfo[_tokenId].owner, _amountXBonus);
            NFTLogic.setXBonusToke(_tokenId,0);
        }
        uint256 _amountBonus = Bonus.getBonus(_tokenId);
        if(_amountBonus > 0 && tokenInfo[_tokenId].owner != _msgSender()){
            UserTotalWithdrawalBonus[tokenInfo[_tokenId].owner] += _amountBonus;
            Bonus.transferMarket(tokenInfo[_tokenId].owner, _amountBonus);
            NFTLogic.setBonusToke(_tokenId,0);
        }
    }

    function withdraw() public {
        uint256 _star = userStar[_msgSender()];
        require(_star > 0, "no star");
        userStar[_msgSender()] = 0;
        starToken.safeTransfer(_msgSender(), _star);

    }

    function getUserTokens(address _user) view external returns (uint256[] memory) {
        return userTokens[_user];
    }

    function setBonusAddress(address _bonus) public onlyOwner {
        bonusAddr = _bonus;
        Bonus = IBonus(bonusAddr);
    }

    function setNFTLogic(address _addr) onlyOwner public {
        require(address(0) != _addr, "NFT address error");
        NFTLogic = INFTLogic(_addr);
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    function setStarNFT(address _starNFT) onlyOwner public {
        require(_starNFT != address(0), "");
        starNFT = IERC721(_starNFT);
    }
}