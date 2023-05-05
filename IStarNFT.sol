// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStarNFT {
    function mint(address _owner, uint256 _cateId, uint256 _newTokenId) external returns (uint256);
    function setCateURI(uint256 _cateId, string memory _cateUri) external;
    function massVerifyOwner(address owner, uint256[] memory _tokenIds) view external returns (bool);
    function massBurn(uint256[] memory _tokenIds) external;
    function setSale(bool _sale) external;
    function balanceOf(address owner) view external returns (uint256);
    function tokenOfOwnerByIndex(address owner,uint256 tokenid) view external returns (uint256);
    function crossChainBurn(uint256  tokenId) external;
    function ownerOf(uint256 tokenId) view external returns (address);
}