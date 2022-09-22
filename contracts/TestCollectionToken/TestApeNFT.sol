// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyNFT is ERC721, Ownable {
    uint256 public totalSupply;
    constructor() ERC721("MyNFT", "ApeTESTERC721") {}

    function safeMint(address to) public {
        totalSupply++;
        _safeMint(to, totalSupply);
    }
}