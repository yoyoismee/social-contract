// SPDX-License-Identifier: MIT
// author : yoyoismee.eth <- feel free to send me beer!
// 01010011 01101111 01100011 01101001 01100001 01101100  01000011 01101111 01101110 01110100 01110010 01100001 01100011 01110100

pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "./SocialContract.sol";

contract SocialFactory {
    event NewContract(address deployedAddress);

    address immutable implementatation;

    constructor() {
        implementatation = address(new SocialContract());
    }

    function deploy(
        uint256 _unlockTime,
        address[] memory members_,
        uint32[] memory shares_,
        uint32[] memory votingRight_,
        uint32[] memory nonVotingShare_,
        uint32[] memory mixShare_,
        uint32[] memory minShare_
    ) external returns (address) {
        address clone = ClonesUpgradeable.clone(implementatation);
        SocialContract(payable(clone)).init(
            _unlockTime,
            members_,
            shares_,
            votingRight_,
            nonVotingShare_,
            mixShare_,
            minShare_
        );
        emit NewContract(clone);
        return clone;
    }
}
