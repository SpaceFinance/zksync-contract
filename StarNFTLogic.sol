// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IStarNFT.sol";
import "./Owned.sol";

interface IERC20Burnable is IERC20 {
    function burnFrom(address account, uint256 amount) external;
}

interface IBonus {
    function getlockRatio() view external returns (uint256);
    function getlockAddress() view external returns (address);
    function addTotalAmount(uint256) external;
    function transferMarket(address _owner,uint256 _amount) external;
    function getTotalAmount() view external returns (uint256);
    function addXTotalAmount(uint256) external;  
    function getXTotalAmount() view external returns (uint256); 
    function transferLogic(address _owner,uint256 _amount) external;   
    function XtransferLogic(address _owner,uint256 _amount) external;
    function getBonus(uint256 _tokenId) view external returns (uint256);
    function getXBonus(uint256 _tokenId) view external returns (uint256);

}

interface IAirdrop {
    function setUser(address _user, uint256 _type) external;
}

interface IXStarToken {
    function balanceOf(address account) external returns (uint256);
    function burnFrom(address account, uint256 amount) external;
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function StarBurnFrom(uint256 amount) external;
}

contract StarNFTLogic is owned {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private cateIds;

    struct StarCate {
        uint256 maxUnit;
        uint256 multiple;
        uint256 usedUnit;
    }

    struct StarMeta {
        StarLevel level;
        uint256 cateId;
        uint256 price;
        uint256 multiple;
        uint256 createTime;
    }

    struct LevelMethod {
        uint256 usedUnit;
        uint256 burned;
        uint256 price;
        bool isInc;
        uint256 base;
        uint256 step;
        bool isUnique;
    }

    struct BonusInfo {
        uint256 totalAmount;
        uint256 rewardDebt;
        uint256 size;
        uint256 loopNumber;
        uint256 nextNumber;
        uint256 lastTimestamp;
        uint256 spaceTimestamp;
    }

    struct XBonusInfo {
        uint256 totalAmount;
        uint256 rewardDebt;
        uint256 size;
        uint256 loopNumber;
        uint256 nextNumber;
        uint256 lastTimestamp;
        uint256 spaceTimestamp;
    }

    enum StarLevel {
        COMMON,
        SPECIAL,
        EXCLUSIVE
    }

    IERC20Burnable public starToken;
    IXStarToken public XstarToken;           
    IBonus private Bonus;
    IStarNFT public starNFT;
    address public bonusAddr;
    address public marketAddr;
    address public crossChainAddr;             
    uint256 public totalPrice;
    uint256 public fee;
    uint256 public number;
    uint256 public surplusReward;
    uint256 public xsurplusReward;
    uint256 public Xprice;         
    uint256[] public topLevelMultiple;
    uint256[] public _allTokensId;
    BonusInfo public bonusInfo;
    XBonusInfo public XbonusInfo;
    IAirdrop public Airdrop;
    mapping(uint256 => StarCate) public cateId;
    mapping(StarLevel => uint256[]) public starCate;
    mapping(StarLevel => LevelMethod) public levelMethod;
    mapping(uint256 => StarMeta) public starMeta;
    mapping (uint256 => uint256) public bonusToken;
    mapping (uint256 => uint256) public XbonusToken;
    mapping(uint256 => uint256) public TokenIdKey;
    mapping(StarLevel => uint256[]) public LevelWeight;
    mapping(uint256 => bool) public XSpaceNFTStatus;
    mapping(uint256 => uint256) public XSpacePrice;
    event Injection(address user, uint256 amount);
    event XMint(address indexed User, uint256 tokenId, uint256 Price);

    constructor(address _starToken, address _bonus, address _starNFT, uint256 _fee) {
        starToken = IERC20Burnable(_starToken);
        starNFT = IStarNFT(_starNFT);
        bonusAddr = _bonus;
        Bonus = IBonus(bonusAddr);
        fee = _fee;
    }

    //mint function
    function mint() public returns (uint256) {
        uint256 _cateId = starCate[StarLevel.COMMON][getRndCateIndex(StarLevel.COMMON)];
        LevelMethod storage _levelMethod = levelMethod[StarLevel.COMMON];
        uint256 _price = _levelMethod.price;
        require(_price > 0, "level price error");
        if (_levelMethod.isInc && _levelMethod.base > 0) {
            _price = _price.add(_levelMethod.usedUnit.mod(_levelMethod.base).mul(_levelMethod.step));
        }
        uint256 indexLength = _allTokensId.length;
        uint256 _fee = _price.mul(fee).div(100);
        uint256 lockRatio = Bonus.getlockRatio();
        starToken.transferFrom(_msgSender(), address(this), _price);
        starToken.burnFrom(address(this), _price.sub(_fee));
        starToken.transferFrom(address(this), bonusAddr, _fee.mul(100 - lockRatio).div(100));
        starToken.transferFrom(address(this), Bonus.getlockAddress(), _fee.mul(lockRatio).div(100));
        uint256 _starId = starNFT.mint(_msgSender(), _cateId,0);
        uint256 _multi = cateId[_cateId].multiple;
        starMeta[_starId] = StarMeta(StarLevel.COMMON, _cateId, _price, _multi,block.timestamp);
        cateId[_cateId].usedUnit += 1;
        _levelMethod.usedUnit += 1;
        Bonus.addTotalAmount(_fee.mul(100 - lockRatio).div(100));
        if(indexLength == 0){
            uint256 balance = starToken.balanceOf(bonusAddr);
            uint256 Xbalance = XstarToken.balanceOf(bonusAddr);
            bonusInfo.rewardDebt.add(_fee.mul(100 - lockRatio).div(100));
            XbonusInfo.rewardDebt.add(_fee.mul(100 - lockRatio).div(100));
            if(balance > 0){
                uint256 UserBonusToken = bonusToken[_starId];
                bonusToken[_starId] = UserBonusToken.add(balance);
            }
            if(Xbalance > 0){
                uint256 XUserBonusToken = XbonusToken[_starId];
                XbonusToken[_starId] = XUserBonusToken.add(balance);
            }
        }
        _allTokensId.push(_starId);
        TokenIdKey[_starId] = _allTokensId.length - 1;
        totalPrice = totalPrice.add(_price.mul(_multi).div(100));
        Airdrop.setUser(_msgSender(),3);
        return _starId;
    }

    //Xmint function 
    function Xmint() public returns (uint256) {
        uint256 _cateId = starCate[StarLevel.COMMON][getRndCateIndex(StarLevel.COMMON)];
        LevelMethod storage _levelMethod = levelMethod[StarLevel.COMMON];
        uint256 _price = _levelMethod.price;
        require(_price > 0, "level price error");
        if (_levelMethod.isInc && _levelMethod.base > 0) {
            _price = _price.add(_levelMethod.usedUnit.mod(_levelMethod.base).mul(_levelMethod.step));
        }
        uint256 _starId = starNFT.mint(_msgSender(), _cateId,0);
        uint256 _multi = cateId[_cateId].multiple;
        uint256 _fee = Xprice.mul(fee).div(100);
        uint256 lockRatio = Bonus.getlockRatio();
        uint256 indexLength = _allTokensId.length;
        XstarToken.burnFrom(_msgSender(), Xprice.sub(_fee));
        XstarToken.StarBurnFrom(Xprice.sub(_fee));
        XstarToken.transferFrom(_msgSender(), bonusAddr, _fee.mul(100 - lockRatio).div(100));
        XstarToken.transferFrom(_msgSender(), Bonus.getlockAddress(), _fee.mul(lockRatio).div(100));
        Bonus.addXTotalAmount(_fee.mul(100 - lockRatio).div(100));
        if(indexLength == 0){
            uint256 balance = starToken.balanceOf(bonusAddr);
            uint256 Xbalance = XstarToken.balanceOf(bonusAddr);
            bonusInfo.rewardDebt.add(_fee.mul(100 - lockRatio).div(100));
            XbonusInfo.rewardDebt.add(_fee.mul(100 - lockRatio).div(100));
            if(balance > 0){
                uint256 UserBonusToken = bonusToken[_starId];
                bonusToken[_starId] = UserBonusToken.add(balance);
            }
            if(Xbalance > 0){
                uint256 XUserBonusToken = XbonusToken[_starId];
                XbonusToken[_starId] = XUserBonusToken.add(balance);
            }
        }
        starMeta[_starId] = StarMeta(StarLevel.COMMON, _cateId, _price, _multi,block.timestamp);
        XSpacePrice[_starId] = Xprice;
        cateId[_cateId].usedUnit += 1;
        _levelMethod.usedUnit += 1;
        _allTokensId.push(_starId);
        TokenIdKey[_starId] = _allTokensId.length - 1;
        totalPrice = totalPrice.add(_price.mul(_multi).div(100));
        XSpaceNFTStatus[_starId] = true;
        emit XMint(_msgSender(), _starId, Xprice);
        return _starId;
    }

    function melt(uint256[] memory _tokenIds, StarLevel _from, StarLevel _to) public returns (uint256) {
        require(uint256(_to) == uint256(_from) + 1, "melt level error");
        require(starNFT.massVerifyOwner(_msgSender(), _tokenIds), "not your tokens");
        (uint256 _price, uint256 _multiple) = verifyTokens(_from, _to, _tokenIds);
        require(_price != 0, "token error");
        starNFT.massBurn(_tokenIds);
        uint256 TransferBonus = 0;
        uint256 XTransferBonus = 0;
        for (uint256 i = 0 ; i < _tokenIds.length; i ++) {
            TransferBonus = TransferBonus.add(bonusToken[_tokenIds[i]]);
            XTransferBonus = XTransferBonus.add(XbonusToken[_tokenIds[i]]);
            TokenIdKey[_allTokensId[_allTokensId.length-1]] = TokenIdKey[_tokenIds[i]];
            _allTokensId[TokenIdKey[_tokenIds[i]]] = _allTokensId[_allTokensId.length-1];
            _allTokensId[_allTokensId.length-1] = _tokenIds[i];
            _allTokensId.pop();
            delete TokenIdKey[_tokenIds[i]];
            uint256 price = starMeta[_tokenIds[i]].price;
            uint256 multiple = starMeta[_tokenIds[i]].multiple;
            uint256 currentPrice = price.mul(multiple).div(100);
            totalPrice = totalPrice.sub(currentPrice);
        }
        levelMethod[_from].burned += _tokenIds.length;
        uint256 _cateId = starCate[_to][getRndCateIndex(_to)];
        uint256 _starId = starNFT.mint(_msgSender(), _cateId,0);
        uint256 _multi = 0;
        if(uint256(_to) == 2){
            _multi = topLevelMultiple[number];
            number++;
        }else{
            _multi = _multiple.mul(cateId[_cateId].multiple).div(100);
        }
        starMeta[_starId] = StarMeta(_to, _cateId, _price, _multi,block.timestamp);
        cateId[_cateId].usedUnit += 1;
        levelMethod[_to].usedUnit += 1;
        totalPrice = totalPrice.add(_price.mul(_multi).div(100));
        bonusToken[_starId] = TransferBonus;
        XbonusToken[_starId] = XTransferBonus;
        _allTokensId.push(_starId);
        TokenIdKey[_starId] = _allTokensId.length - 1;
        return _starId;
    }

    //######################################## begin ####################################
    function CrossChainBurnLogicProcessing(uint256 _tokenId,uint256[] memory _tokenIds,address _user) external onlyCrossChain{
        require(starNFT.massVerifyOwner(_user, _tokenIds), "not your tokens");
        starNFT.massBurn(_tokenIds);
        uint256 _amountXBonus = Bonus.getXBonus(_tokenId);
        if(_amountXBonus > 0){
            Bonus.XtransferLogic(_user, _amountXBonus);
            XbonusToken[_tokenId] = 0;
        }
        uint256 _amountBonus = Bonus.getBonus(_tokenId);
        if(_amountBonus > 0 ){
            Bonus.transferLogic(_user, _amountBonus);
            bonusToken[_tokenId] = 0;
        }
        TokenIdKey[_allTokensId[_allTokensId.length-1]] = TokenIdKey[_tokenId];
        _allTokensId[TokenIdKey[_tokenId]] = _allTokensId[_allTokensId.length-1];
        _allTokensId[_allTokensId.length-1] = _tokenId;
        _allTokensId.pop();
        delete TokenIdKey[_tokenId];
        uint256 price = starMeta[_tokenId].price;
        uint256 multiple = starMeta[_tokenId].multiple;
        uint256 currentPrice = price.mul(multiple).div(100);
        totalPrice = totalPrice.sub(currentPrice);
    }

    function CrossChainMintLogicProcessing(address _mintUser,StarLevel _level,uint256 _cateId,uint256 _price,uint256 _newTokenId,uint256 _multi) external onlyCrossChain returns(uint256){
        uint256 _starId = starNFT.mint(_mintUser, _cateId,_newTokenId);
        starMeta[_starId] = StarMeta(_level, _cateId, _price, _multi,block.timestamp);
        _allTokensId.push(_starId);
        totalPrice = totalPrice.add(_price.mul(_multi).div(100));
        Airdrop.setUser(_mintUser,3);
        return _starId;
    }

    function setCrossChain(address _crossChainAddr) onlyOwner public {
        require(address(0) != _crossChainAddr, "crossChain address can not be address 0");
        crossChainAddr = _crossChainAddr;
    }

    modifier onlyCrossChain() {
        require(_msgSender() == crossChainAddr, "no permission");
        _;
    }
    //######################################## end ####################################

    function verifyTokens(StarLevel _level, StarLevel _newLevel, uint256[] memory _tokenIds) view internal returns (uint256, uint256) {
        LevelMethod memory _levelMethod = levelMethod[_newLevel];
        uint256 _price = _levelMethod.price;
        if (_levelMethod.isInc && _levelMethod.base > 0) {
            _price = _price.add(_levelMethod.usedUnit.div(_levelMethod.base).mul(_levelMethod.step));
        }
        require(_tokenIds.length == _price, "token amount error");
        uint256 multiple;
        uint256 price;
        uint256[] memory _cateIds = new uint256[](_tokenIds.length);
        for (uint256 i = 0; i < _tokenIds.length; i ++) {
            require(starMeta[_tokenIds[i]].level == _level, "error level");
            price = price.add(starMeta[_tokenIds[i]].price);
            multiple = multiple.add(starMeta[_tokenIds[i]].multiple);
            if (!_levelMethod.isUnique) {
                require(!indexOf(_cateIds, starMeta[_tokenIds[i]].cateId), "must be unique cate");
            }
            _cateIds[i] = starMeta[_tokenIds[i]].cateId;
        }
        return (price, multiple.div(_tokenIds.length));
    }

    function injection(uint256 _amount) public {
        starToken.transferFrom(_msgSender(), bonusAddr, _amount);
        uint256 indexLength = _allTokensId.length;
        if(indexLength > 0){
            for(uint256 i = 0;i< indexLength;i++){
                uint256 tokenId = _allTokensId[i];
                uint256 _tokenIdPrice = starMeta[tokenId].price;
                uint256 _tokenIdMultiple = starMeta[tokenId].multiple;
                uint256 Price = _tokenIdPrice.mul(_tokenIdMultiple).div(100);
                uint256 Ratio = Price.mul(1e12).div(totalPrice);
                uint256 divAmountBonus = _amount.mul(Ratio).div(1e12);
                uint256 UserBonusToken = bonusToken[tokenId];
                bonusToken[tokenId] = divAmountBonus.add(UserBonusToken);
            }
        }
        bonusInfo.rewardDebt.add(_amount);
        Bonus.addTotalAmount(_amount);
        emit Injection(_msgSender(), _amount);
    }

    function getMeltverifyStatus(StarLevel _level, StarLevel _newLevel,uint256[] memory _tokenIds) public view returns (bool) {
        LevelMethod memory _levelMethod = levelMethod[_newLevel];
        uint256 _price = _levelMethod.price;
        if (_levelMethod.isInc && _levelMethod.base > 0) {
            _price = _price.add(_levelMethod.usedUnit.div(_levelMethod.base).mul(_levelMethod.step));
        }
        if(_tokenIds.length != _price) return false;
        uint256[] memory _cateIds = new uint256[](_tokenIds.length);
        for (uint256 i = 0; i < _tokenIds.length; i ++) {
            if(starMeta[_tokenIds[i]].level != _level) return false;
            if (!_levelMethod.isUnique) {
                if(indexOf(_cateIds, starMeta[_tokenIds[i]].cateId)) return false;
            }
            _cateIds[i] = starMeta[_tokenIds[i]].cateId;
        }
        return true;
    }

    function getCateLength(StarLevel _level) internal view returns (uint256) {
        return starCate[_level].length;
    }

    function getRndCateIndex(StarLevel _level) view public returns (uint256) {
        uint256[] storage _cate = starCate[_level];
        require(_cate.length > 0, "no cate");
        uint256 _rndCateIndex;
        uint256 nonce;
        if(uint256(_level) == 2){
            do {
                _rndCateIndex = uint256(keccak256(abi.encodePacked(block.coinbase, msg.sender, nonce, block.timestamp))) % _cate.length;
                if (cateId[_cate[_rndCateIndex]].maxUnit > cateId[_cate[_rndCateIndex]].usedUnit) break;
                nonce ++;
            } while (true);
        }else{
            do {
                uint256 _rndCateNumber = uint256(keccak256(abi.encodePacked(block.coinbase, msg.sender, nonce, block.timestamp))) % 120;
                for(uint256 i = 0;i < LevelWeight[_level].length;i++){
                    if(_rndCateNumber >= LevelWeight[_level][i] && _rndCateNumber < LevelWeight[_level][i+1]){
                        _rndCateIndex = i / 2;
                        break;
                    }
                }
                if (cateId[_cate[_rndCateIndex]].maxUnit > cateId[_cate[_rndCateIndex]].usedUnit) break;
                nonce ++;
            } while (true);
        }
        return _rndCateIndex;
    }

    function addCate(StarLevel _level, uint256 _maxUnit, uint256 _multiple, string memory _cateUri) onlyOwner public {
        cateIds.increment();
        uint256 _cateId = cateIds.current();
        cateId[_cateId] = StarCate(_maxUnit, _multiple, 0);
        starCate[_level].push(_cateId);
        starNFT.setCateURI(_cateId, _cateUri);
    }

    function editCate(uint256 _cateId, uint256 _maxUnit, uint256 _multiple, string memory _cateUri) onlyOwner public {
        StarCate storage _cate = cateId[_cateId];
        _cate.maxUnit = _maxUnit;
        _cate.multiple = _multiple;
        starNFT.setCateURI(_cateId, _cateUri);
    }

    function setLevelMethod(StarLevel _level, uint256 _price, bool _isInc, uint256 _base, uint256 _step, bool _isUnique) onlyOwner public {
        LevelMethod storage _levelMethod = levelMethod[_level];
        _levelMethod.price = _price;
        _levelMethod.isInc = _isInc;
        _levelMethod.base = _base;
        _levelMethod.step = _step;
        _levelMethod.isUnique = _isUnique;
    }

    function setTopLevelMultiple(uint256[] memory _multiples) onlyOwner public{
        topLevelMultiple = _multiples;
    }

    function disposeBonusToke(uint256 _tokenId) view external returns (uint256) {
        return bonusToken[_tokenId];
    }

    function disposeXBonusToke(uint256 _tokenId) view external returns (uint256) {
        return XbonusToken[_tokenId];
    }

    function getStarMeta(uint256 _tokenId) view external returns (uint256,uint256) {
        return (starMeta[_tokenId].price,starMeta[_tokenId].multiple);
    }

    function getTokensId(uint256 _index) view public returns(uint256){
        return _allTokensId[_index];
    }

    function getAllTokenId() view external returns(uint256[] memory){
        return  _allTokensId;
    }

    // @error Exception to be handled
    function setBonusToke(uint256 _tokenId,uint256 _amountBonus) external onlyPower {
        bonusToken[_tokenId] = _amountBonus;
    }

    function setXBonusToke(uint256 _tokenId,uint256 _amountBonus) external onlyPower {
        XbonusToken[_tokenId] = _amountBonus;
    }

    function setAllBonusToke() public {
        if(surplusReward == 0 && block.timestamp > bonusInfo.lastTimestamp.add(bonusInfo.spaceTimestamp)){
            bonusInfo.size = _allTokensId.length;
            uint256 totalAmount = Bonus.getTotalAmount();
            surplusReward = totalAmount.sub(bonusInfo.rewardDebt);
        }
        if(surplusReward > 0){
            uint256 endNumber;
            if(bonusInfo.size >= bonusInfo.nextNumber.add(bonusInfo.loopNumber)){
                endNumber = bonusInfo.nextNumber.add(bonusInfo.loopNumber);
            }else{
                endNumber = bonusInfo.size;
            }
            for(uint256 i = bonusInfo.nextNumber;i< endNumber;i++){
                uint256 _tokenId = _allTokensId[i];
                uint256 _tokenIdPrice = starMeta[_tokenId].price;
                uint256 _tokenIdMultiple = starMeta[_tokenId].multiple;
                uint256 Price = _tokenIdPrice.mul(_tokenIdMultiple).div(100);
                uint256 divAmountBonus = surplusReward.mul(Price).div(totalPrice);
                bonusToken[_tokenId] = divAmountBonus.add(bonusToken[_tokenId]);
                if(i == bonusInfo.size-1){
                    bonusInfo.rewardDebt = Bonus.getTotalAmount();
                    bonusInfo.totalAmount = 0;
                    bonusInfo.size = 0;
                    bonusInfo.nextNumber = 0;
                    bonusInfo.lastTimestamp = block.timestamp;
                    surplusReward = 0;
                    break;
                }else{
                    bonusInfo.nextNumber = endNumber;
                }
            }
        }
    }

    function setXAllBonusToke() public {
        if(xsurplusReward == 0 && block.timestamp > XbonusInfo.lastTimestamp.add(XbonusInfo.spaceTimestamp)){
            XbonusInfo.size = _allTokensId.length;
            uint256 totalAmount = Bonus.getXTotalAmount();
            xsurplusReward = totalAmount.sub(XbonusInfo.rewardDebt);
        }
        if(xsurplusReward > 0){
            uint256 endNumber;
            if(XbonusInfo.size >= XbonusInfo.nextNumber.add(XbonusInfo.loopNumber)){
                endNumber = XbonusInfo.nextNumber.add(XbonusInfo.loopNumber);
            }else{
                endNumber = XbonusInfo.size;
            }
            for(uint256 i = XbonusInfo.nextNumber;i< endNumber;i++){
                uint256 _tokenId = _allTokensId[i];
                uint256 _tokenIdPrice = starMeta[_tokenId].price;  
                uint256 _tokenIdMultiple = starMeta[_tokenId].multiple;
                uint256 Price = _tokenIdPrice.mul(_tokenIdMultiple).div(100);
                uint256 divAmountBonus = xsurplusReward.mul(Price).div(totalPrice);
                XbonusToken[_tokenId] = divAmountBonus.add(XbonusToken[_tokenId]);
                if(i == XbonusInfo.size-1){
                    XbonusInfo.rewardDebt = Bonus.getXTotalAmount();
                    XbonusInfo.totalAmount = 0;
                    XbonusInfo.size = 0;
                    XbonusInfo.nextNumber = 0;
                    XbonusInfo.lastTimestamp = block.timestamp;
                    xsurplusReward = 0;
                    break;
                }else{
                    XbonusInfo.nextNumber = endNumber;
                }
            }
        }
    }

    function setXBonusInfo(uint256 _loopNumber, uint256 _spaceTimestamp) onlyOwner public {
        XbonusInfo.loopNumber = _loopNumber;
        XbonusInfo.spaceTimestamp = _spaceTimestamp;
    }

    function getXSpaceNFTStatus(uint256 _tokenId) view public returns(bool){
        require(_tokenId > 0, "TokenId must be greater than 0");
        if (XSpaceNFTStatus[_tokenId] == true) {
            return true;
        }
        return false;
    }

    function setBonusInfo(uint256 _loopNumber, uint256 _spaceTimestamp) onlyOwner public {
        bonusInfo.loopNumber = _loopNumber;
        bonusInfo.spaceTimestamp = _spaceTimestamp;
    }

    function setXprice(uint256 _price) onlyOwner public {
        require(_price > 0, "price must be greater than 0");
        Xprice = _price;
    }
    
    function setStarNFT(address _starNFT) onlyOwner public {
        require(_starNFT != address(0), "address error");
        starNFT = IStarNFT(_starNFT);
    }

    function setBonus(address _bonus) onlyOwner public {
        require(_bonus != address(0), "address error");
        bonusAddr = _bonus;
        Bonus = IBonus(bonusAddr);
    }

    function setXStarToken(address _xstarToken) onlyOwner public {
        require(_xstarToken != address(0), "address error");
        XstarToken = IXStarToken(_xstarToken);
    }

    function setNFTMarket(address _marketAddr) onlyOwner public {
        marketAddr = _marketAddr;
    }

    function setAirdrop(address _addr) external onlyOwner {
        require(address(0) != _addr, "bonus address can not be address 0");
        Airdrop = IAirdrop(_addr);
    }

    function setLevelWeight(StarLevel _level,uint256[] memory _weight) onlyOwner public {
        LevelWeight[_level] = _weight;
    }

    function indexOf(uint256[] memory A, uint256 a) internal pure returns (bool) {
        uint256 length = A.length;
        for (uint256 i = 0; i < length; i++) {
            if (A[i] == a) {
                return true;
            }
        }

        return false;
    }

    modifier onlyPower() {
        require(_msgSender() == bonusAddr || _msgSender() == marketAddr, "no permission");
        _;
    }
}