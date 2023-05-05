// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Owned.sol";

interface IStarFarm {
    function regNodeUser(address _user) external;
}

interface IERC20Burnable is IERC20 {
    function burnFrom(address account, uint256 amount) external;
    function StarBurnFrom(uint256 amount) external;
}

interface IBonus {
    function getlockRatio() view external returns (uint256);
    function getlockAddress() view external returns (address);
    function addTotalAmount(uint256) external;
    function addXTotalAmount(uint256) external;
}

interface IAirdrop {
    function setUser(address _user, uint256 _type) external;
}

contract StarNode is owned {
    using Counters for Counters.Counter;
    Counters.Counter private _nodeIds;
    using SafeMath for uint256;
    using SafeERC20 for IERC20Burnable;

    struct Node {
        uint256 totalUnit;
        uint256 burn;
        uint256 award;
        uint256 xaward;
        uint256 withdraw;
        uint256 xwithdraw;
        address owner;
        bytes4 code;
        uint256 fee;
        string name;
        string social;
    }

    struct UserNode {
        uint256 award;
        uint256 withdraw;
        uint256 totalAward;
        uint256 xaward;
        uint256 xwithdraw;
        uint256 xtotalAward;
    }

    struct NodeLp {
        uint256 awardLp;
        uint256 withdrawLp;
    }

    struct UserNodeLp {
        uint256 awardLp;
        uint256 withdrawLp;
        uint256 totalAwardLp;
    }

    IERC20Burnable public starToken;
    IERC20Burnable public xToken;
    IBonus public Bonus;
    IStarFarm public starFarm;
    IAirdrop public Airdrop;
    address public bonusAddr;
    address public farmLib;
    uint256 selfGain;      // self addtional gain 100 = 1%
    uint256 parentGain;    // parent addtional gain 100 = 1%
    uint256 public unitPrice;
    uint256 public leastUnit;
    uint256 public fee;
    uint256 public userNumber;
    uint256 public award;
    uint256 public xaward;
    Node[] public nodes;
    address[] public nodeLpArr;

    mapping(address => uint256) public nodeInfo;
    mapping(address => uint256) public awardLp;
    mapping(address => address) public userInviter;
    mapping(address => address[]) public nodeUsers;
    mapping(address => UserNode) public awardNodeUsers;
    mapping(string => address[]) public nameUsers;
    mapping(string => mapping(address => uint256)) public nameUsersIndex;

    mapping(uint256 => mapping(address => NodeLp)) public nodeLp;
    mapping(address => uint256) public nodeLpIndex;
    mapping(address => mapping(address => UserNodeLp)) public userNodeLp;
    mapping(address => address[]) public userLp;
    mapping(address => mapping(address => uint256)) public userLpIndex;
    mapping(uint256 => string) public nodeNotes;
    mapping(uint256 => uint256) public nodeXburn;
    mapping(uint256 => uint256) public nodeXfee;
    mapping(uint256 => uint256) public nodeFeeType;
    struct SlotInfo {
        uint256 _amount;
        uint256 _xamount;
        uint256 nodeFee;
        uint256 lockRatio;
        address lockAddr;
        uint256 amountBonus;
    }
    uint256 public xunitPrice;

    event SettleNode(address _user, uint256 _amount, uint256 _xamount);
    event SettleNodeLp(address _user, address _lpAddr, uint256 _amount);
    event Received(address, uint);

    constructor(address _starToken, address _xToken, address _bonus, uint256 _selfGain, uint256 _parentGain, uint256 _unitPrice, uint256 _xunitPrice, uint256 _leastUnit, uint256 _fee) {
        starToken = IERC20Burnable(_starToken);
        xToken = IERC20Burnable(_xToken);
        bonusAddr = _bonus;
        Bonus = IBonus(bonusAddr);
        _set(_selfGain, _parentGain, _unitPrice, _xunitPrice, _leastUnit);
        fee = _fee;
    }

    function _set(uint256 _selfGain, uint256 _parentGain, uint256 _unitPrice, uint256 _xunitPrice, uint256 _leastUnit) internal {
        selfGain = _selfGain;
        parentGain = _parentGain;
        unitPrice = _unitPrice;
        xunitPrice = _xunitPrice;
        leastUnit = _leastUnit;
    }

    function nodeGain(address _user) external view returns (uint256 _selfGain, uint256 _parentGain) {
        address _inviter = userInviter[_user];
        if (address(0) != _inviter) {
            return (selfGain, parentGain);
        }else{
            return (0, 0);
        }
    }

    function nodeLength() public view returns (uint256) {
        return nodes.length;
    }

    function getNodeUsers(address _user) public view returns (address[] memory) {
        return nodeUsers[_user];
    }

    function nodeUserLength(address _user) public view returns (uint256) {
        return nodeUsers[_user].length;
    }

    function nameUsersLength(string memory _name) public view returns (uint256) {
        return nameUsers[_name].length;
    }

    function getNode(address _user) public view returns(uint256 _totalUnit, uint256 _burn, uint256 _award, uint256 _xaward, uint256 _withdraw, uint256 _xwithdraw, address _owner, uint256 _fee, string memory _nodeName, string memory _social) {
        _totalUnit = nodes[nodeInfo[_user]].totalUnit;
        _burn = nodes[nodeInfo[_user]].burn;
        _award = nodes[nodeInfo[_user]].award;
        _xaward = nodes[nodeInfo[_user]].xaward;
        _withdraw = nodes[nodeInfo[_user]].withdraw;
        _xwithdraw = nodes[nodeInfo[_user]].xwithdraw;
        _owner = nodes[nodeInfo[_user]].owner;
        _fee = nodes[nodeInfo[_user]].fee;
        _nodeName = nodes[nodeInfo[_user]].name;
        _social = nodes[nodeInfo[_user]].social;
    }

    function depositNode(uint256 _unit, bool _usexToken, uint256 _nodeFeeType, uint256 _fee, uint256 _xfee, string memory _name, string memory _social, string memory _notes) external {
        SlotInfo memory slot;
        address _user = _msgSender();
        require(userInviter[_user] == address(0), "User must not node user");
        require(_unit > 0, "Uint must greater than 0");
        slot._amount = _unit.mul(unitPrice);
        slot._xamount = _unit.mul(xunitPrice);
        if(_usexToken == false){
            slot.nodeFee = slot._amount.mul(fee).div(100);
            require(slot._amount > 0, "amount err");
            starToken.burnFrom(_user, slot._amount.mul(100 - fee).div(100));
        }else{
            slot.nodeFee = slot._xamount.mul(fee).div(100);
            require(slot._xamount > 0, "amount err");
            xToken.burnFrom(_user, slot._xamount.mul(100 - fee).div(100));
            xToken.StarBurnFrom(slot._xamount.mul(100 - fee).div(100));
        }
        slot.lockRatio = Bonus.getlockRatio();
        slot.lockAddr = Bonus.getlockAddress();
        slot.amountBonus;
        if (nodes.length == 0 || nodes[nodeInfo[_user]].owner != _user) {    // New node.
            require(_unit >= leastUnit, "Less than minimum limit");
            nodes.push(Node(_unit, slot._amount, 0, 0, 0, 0, _user, getRndId(_user), _fee, _name, _social));
            nodeInfo[_user] = nodes.length - 1;
            nodeFeeType[nodes.length - 1] = _nodeFeeType;
            nodeXfee[nodes.length - 1] = _xfee;
            nodeNotes[nodes.length - 1] = _notes;
            nameUsers[_name].push(_user);
            nameUsersIndex[_name][_user] = nameUsers[_name].length - 1;
            if(_usexToken == false){
                starToken.transferFrom(_user, slot.lockAddr, slot.nodeFee.mul(slot.lockRatio).div(100));
                slot.amountBonus = slot.nodeFee.mul(100 - slot.lockRatio).div(100);
                starToken.transferFrom(_user, bonusAddr, slot.amountBonus);
                Bonus.addTotalAmount(slot.amountBonus);
            }else{
                xToken.transferFrom(_user, slot.lockAddr, slot.nodeFee.mul(slot.lockRatio).div(100));
                slot.amountBonus = slot.nodeFee.mul(100 - slot.lockRatio).div(100);
                xToken.transferFrom(_user, bonusAddr, slot.amountBonus);
                Bonus.addXTotalAmount(slot.amountBonus);
                nodeXburn[nodeInfo[_user]] = nodeXburn[nodeInfo[_user]].add(slot._xamount);
            }
            userNumber = userNumber.add(1);
            Airdrop.setUser(_user,2);
        } else {
            Node storage node =  nodes[nodeInfo[_user]];
            node.totalUnit = node.totalUnit.add(_unit);
            if(_usexToken == false){
                starToken.transferFrom(_user, slot.lockAddr, slot.nodeFee.mul(slot.lockRatio).div(100));
                slot.amountBonus = slot.nodeFee.mul(100 - slot.lockRatio).div(100);
                starToken.transferFrom(_user, bonusAddr, slot.amountBonus);
                Bonus.addTotalAmount(slot.amountBonus);
                node.burn = node.burn.add(slot._amount);
            }else{
                xToken.transferFrom(_user, slot.lockAddr, slot.nodeFee.mul(slot.lockRatio).div(100));
                slot.amountBonus = slot.nodeFee.mul(100 - slot.lockRatio).div(100);
                xToken.transferFrom(_user, bonusAddr, slot.amountBonus);
                Bonus.addXTotalAmount(slot.amountBonus);
                nodeXburn[nodeInfo[_user]] = nodeXburn[nodeInfo[_user]].add(slot._xamount);
            }
        }
    }

    function regFromNode(address _inviter, bool _useXfee, bytes32 _inviteCode) external {
        address _user = _msgSender();
        require(userInviter[_user] == address(0), "User already registered");
        require(nodeInfo[_user] == 0 && nodes[0].owner != _user, "You are node master");
        require(nodeUserLength(_inviter) < nodes[nodeInfo[_inviter]].totalUnit, "Parent node is full");
        require(verifyInvitecode(_user, _inviter, _inviteCode), "Invalid invite code");
        if(nodes[nodeInfo[_inviter]].fee > 0 || nodeXfee[nodeInfo[_inviter]] > 0){
            require(nodeFeeType[nodeInfo[_inviter]] < 3, "err feeType");
            if(_useXfee == false){
                require(nodeFeeType[nodeInfo[_inviter]] < 2, "err feeType");
                starToken.transferFrom(_user, nodes[nodeInfo[_inviter]].owner, nodes[nodeInfo[_inviter]].fee);
            }else{
                require(nodeFeeType[nodeInfo[_inviter]]%2 == 0, "err feeType");
                xToken.transferFrom(_user, address(this), nodeXfee[nodeInfo[_inviter]]);
                xToken.safeTransfer(nodes[nodeInfo[_inviter]].owner, nodeXfee[nodeInfo[_inviter]]);
            }
        }
        nodeUsers[_inviter].push(_user);
        userNumber = userNumber.add(1);
        userInviter[_user] = _inviter;
        starFarm.regNodeUser(_user);
        Airdrop.setUser(_user,2);
    }

    function settleNode(address _user, uint256 _parentAmount, uint256 _selfAmount, uint256 _xparentAmount, uint256 _xselfAmount) external onlyFarmLib {
        address _inviter = userInviter[_user];
        uint256 _amount = _parentAmount + _selfAmount;
        uint256 _xamount = _xparentAmount + _xselfAmount;
        if(_inviter != address(0)){
            award = award.add(_amount);
            nodes[nodeInfo[_inviter]].award = nodes[nodeInfo[_inviter]].award.add(_amount);
            awardNodeUsers[_inviter].award = awardNodeUsers[_inviter].award.add(_parentAmount);
            awardNodeUsers[_inviter].totalAward = awardNodeUsers[_inviter].totalAward.add(_parentAmount);
            awardNodeUsers[_user].award = awardNodeUsers[_user].award.add(_selfAmount);
            awardNodeUsers[_user].totalAward = awardNodeUsers[_user].totalAward.add(_selfAmount);
            nodes[nodeInfo[_inviter]].xaward = nodes[nodeInfo[_inviter]].xaward.add(_xamount);
            awardNodeUsers[_inviter].xaward = awardNodeUsers[_inviter].xaward.add(_xparentAmount);
            awardNodeUsers[_inviter].xtotalAward = awardNodeUsers[_inviter].xtotalAward.add(_xparentAmount);
            awardNodeUsers[_user].xaward = awardNodeUsers[_user].xaward.add(_xselfAmount);
            awardNodeUsers[_user].xtotalAward = awardNodeUsers[_user].xtotalAward.add(_xselfAmount);
            emit SettleNode(_inviter, _amount, _xamount);
        }
    }

    function withdraw() external {
        address _user = _msgSender();
        address _inviter = userInviter[_user];
        if (address(0) == _inviter) {
            require(nodes[nodeInfo[_user]].owner == _user, "Invalid inviter");
            _inviter = _user;
        }
        Node storage node =  nodes[nodeInfo[_inviter]];
        UserNode storage nodeusers =  awardNodeUsers[_user];
        uint256 userAward = nodeusers.award;
        uint256 xuserAward = nodeusers.xaward;
        node.withdraw = node.withdraw.add(userAward);
        nodeusers.withdraw = nodeusers.withdraw.add(userAward);
        nodeusers.award = 0;
        node.xwithdraw = node.xwithdraw.add(xuserAward);
        nodeusers.xwithdraw = nodeusers.xwithdraw.add(xuserAward);
        nodeusers.xaward = 0;
        uint256 len = userLp[_user].length;
		for(uint256 i; i < len; i++){
            address _lpAddr = userLp[_user][i];
		    uint256 userAwardLp = userNodeLp[_user][userLp[_user][i]].awardLp;
            if(userAwardLp > 0) {
                nodeLp[nodeInfo[_inviter]][_lpAddr].withdrawLp = nodeLp[nodeInfo[_inviter]][_lpAddr].withdrawLp.add(userAwardLp);
                userNodeLp[_user][_lpAddr].withdrawLp = userNodeLp[_user][_lpAddr].withdrawLp.add(userAwardLp);
                userNodeLp[_user][_lpAddr].awardLp = 0;
                if(address(_lpAddr) == address(0)){
                    (bool success, ) = _user.call{value:userAwardLp}("");
                    require(success, "Transfer failed.");
                }else{
                    IERC20Burnable(_lpAddr).safeTransfer(_user, userAwardLp);
                }
			}
        }
        starToken.safeTransfer(_user, userAward);
        xToken.safeTransfer(_user, xuserAward);
    }

    //setNodeLp
    function settleNodeLp(address _user, address _lpAddr, uint256 _parentAmount, uint256 _selfAmount) external onlyFarmLib {
        address _inviter = userInviter[_user];
        uint256 _amount = _parentAmount + _selfAmount;
        if(_inviter != address(0)){
            if(nodeLpIndex[_lpAddr] == 0){
                if(nodeLpArr.length > 0){
                    if(nodeLpArr[0] != _lpAddr){
                        nodeLpArr.push(_lpAddr);
                        nodeLpIndex[_lpAddr] = nodeLpArr.length -1;
                    }
                }else{
                    nodeLpArr.push(_lpAddr);
                    nodeLpIndex[_lpAddr] = nodeLpArr.length -1;

                }
            }
            if(userLpIndex[_inviter][_lpAddr] == 0){
                if(userLp[_inviter].length > 0){
                    if(userLp[_inviter][0] != _lpAddr){
                        userLp[_inviter].push(_lpAddr);
                        userLpIndex[_inviter][_lpAddr] = userLp[_inviter].length -1;
                    }
                }else{
                    userLp[_inviter].push(_lpAddr);
                    userLpIndex[_inviter][_lpAddr] = userLp[_inviter].length -1;

                }
            }
            if(userLpIndex[_user][_lpAddr] == 0){
                if(userLp[_user].length > 0){
                    if(userLp[_user][0] != _lpAddr){
                        userLp[_user].push(_lpAddr);
                        userLpIndex[_user][_lpAddr] = userLp[_user].length -1;
                    }
                }else{
                    userLp[_user].push(_lpAddr);
                    userLpIndex[_user][_lpAddr] = userLp[_user].length -1;
                }
            }
            nodeLp[nodeInfo[_inviter]][_lpAddr].awardLp = nodeLp[nodeInfo[_inviter]][_lpAddr].awardLp.add(_amount);
            awardLp[_lpAddr] = awardLp[_lpAddr].add(_amount);
            userNodeLp[_inviter][_lpAddr].awardLp = userNodeLp[_inviter][_lpAddr].awardLp.add(_parentAmount);
            userNodeLp[_inviter][_lpAddr].totalAwardLp = userNodeLp[_inviter][_lpAddr].totalAwardLp.add(_parentAmount);
            userNodeLp[_user][_lpAddr].awardLp = userNodeLp[_user][_lpAddr].awardLp.add(_selfAmount);
            userNodeLp[_user][_lpAddr].totalAwardLp = userNodeLp[_user][_lpAddr].totalAwardLp.add(_selfAmount);
            emit SettleNodeLp(_inviter, _lpAddr, _amount);
        }
    }

    function getNodeLpLength() external view returns(uint256) {
        return nodeLpArr.length;
    }

    function getUserLp(address _user) external view returns(address[] memory) {
        return userLp[_user];
    }

    function getRndId(address _user) internal view returns (bytes4){
        bytes4 _randId = bytes4(keccak256(abi.encodePacked(block.coinbase, block.timestamp, _user)));
        return _randId;
    }

    function verifyInvitecode(address _self, address _inviter, bytes32 _inviteCode) internal view returns (bool _verified) {
        require(nodes[nodeInfo[_inviter]].owner == _inviter, "Invalid inviter");
        if (_inviteCode == keccak256(abi.encodePacked(nodes[nodeInfo[_inviter]].code, _self))) return true;
    }

    function setStarToken(address _starToken) public onlyOwner {
        require(address(0) != _starToken, "empty");
        starToken = IERC20Burnable(_starToken);
    }

    function setBonusAddr(address _bonusAddr) public onlyOwner {
        require(address(0) != _bonusAddr, "empty");
        bonusAddr = _bonusAddr;
        Bonus = IBonus(bonusAddr);
    }

    function setStarFarm(address _addr) public onlyOwner {
        require(address(0) != _addr, "empty");
        starFarm = IStarFarm(_addr);
    }

    function setFarmLib(address _addr) public onlyOwner {
        require(address(0) != _addr, "empty");
        farmLib = _addr;
    }

    function setAirdrop(address _addr) external onlyOwner {
        require(address(0) != _addr, "empty");
        Airdrop = IAirdrop(_addr);
    }

    function setXToken(address _addr) external onlyOwner {
        require(address(0) != _addr, "empty");
        xToken = IERC20Burnable(_addr);
    }

    function setParams(uint256 _selfGain, uint256 _parentGain, uint256 _unitPrice, uint256 _xunitPrice, uint256 _leastUnit) public onlyOwner {
        _set(_selfGain, _parentGain, _unitPrice, _xunitPrice, _leastUnit);
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    function setJoiningFee(uint _nodeFeeType, uint256 _fee, uint256 _useXfee) public {
        require(_msgSender() == nodes[nodeInfo[_msgSender()]].owner, "You are not the node master");
        nodeFeeType[nodeInfo[_msgSender()]] = _nodeFeeType;
        nodes[nodeInfo[_msgSender()]].fee = _fee;
        nodeXfee[nodeInfo[_msgSender()]] = _useXfee;
    }

    function setName(string memory _name) external {
        address _user = _msgSender();
        require(_user == nodes[nodeInfo[_user]].owner, "You are not the node master");
        string memory oldName = nodes[nodeInfo[_user]].name;
        if(nameUsers[oldName].length > 1)
        nameUsers[oldName][nameUsersIndex[_name][_user].sub(1)] = nameUsers[oldName][nameUsers[_name].length-1];
        nameUsers[oldName].pop();
        nodes[nodeInfo[_user]].name = _name;
        nameUsers[_name].push(_user);
        nameUsersIndex[oldName][_user] = 0;
        nameUsersIndex[_name][_user] = nameUsers[_name].length;
    }

    function setSocial(string memory _social) external {
        address _user = _msgSender();
        require(_user == nodes[nodeInfo[_user]].owner, "You are not the node master");
        nodes[nodeInfo[_user]].social = _social;
    }

    function setNotes(string memory _notes) external {
        address _user = _msgSender();
        require(_user == nodes[nodeInfo[_user]].owner, "You are not the node master");
        nodeNotes[nodeInfo[_user]] = _notes;
    }

    function withdrawLp(address _lpAddr) external onlyOwner {
        if(address(_lpAddr) == address(0)){
            (bool success, ) = _msgSender().call{value:address(this).balance}("");
            require(success, "user Transfer failed.");
        }else{
            IERC20Burnable(_lpAddr).safeTransfer(_msgSender(), IERC20Burnable(_lpAddr).balanceOf(address(this)));
        }
    }

    modifier onlyFarmLib() {
        require(_msgSender() == farmLib, "Only allowed from farmLib contract");
        _;
    }

    receive() external payable{
        emit Received(_msgSender(), msg.value);
    }
}