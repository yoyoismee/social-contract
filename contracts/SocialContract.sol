// SPDX-License-Identifier: MIT
// author : yoyoismee.eth <- feel free to send me beer!
// 01010011 01101111 01100011 01101001 01100001 01101100  01000011 01101111 01101110 01110100 01110010 01100001 01100011 01110100

pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @notice learn more at https://github.com/yoyoismee/social-contract
contract SocialContract is Initializable, ContextUpgradeable {
    event ContractCreated(uint256 unlockTime, uint256 totalShare);

    event MemberAdded(
        address account,
        uint32 share,
        uint32 votingRight,
        uint32 nonVotingShare,
        uint32 maxShare,
        uint32 minShare
    );

    event PaymentReleased(address to, uint256 amount);

    event ERC20PaymentReleased(
        IERC20Upgradeable indexed token,
        address to,
        uint256 amount
    );

    event PaymentReceived(address from, uint256 amount);

    struct Share {
        uint32 share;
        uint32 votingRight;
        uint32 nonVotingShare;
        uint32 maxShare;
        uint32 minShare;
    }

    uint256 public totalShare;

    mapping(address => Share) public shares;

    uint256 private totalReleased;

    mapping(address => uint256) public released;

    address[] public members;

    /// can reward and punish before unlock. can redeem after unlock
    uint256 public unlockTime;

    mapping(IERC20Upgradeable => uint256) public erc20TotalReleased;
    mapping(IERC20Upgradeable => mapping(address => uint256))
        public erc20Released;

    function init(
        uint256 _unlockTime,
        address[] memory members_,
        uint32[] memory shares_,
        uint32[] memory votingRight_,
        uint32[] memory nonVotingShare_,
        uint32[] memory mixShare_,
        uint32[] memory minShare_
    ) public initializer {
        /// @dev eh, life too short for param validation. lol ez

        // Avoid to make time-based decisions? nope! don't tell me what to do
        require(unlockTime > block.timestamp);

        unlockTime = _unlockTime;

        for (uint256 i = 0; i < members_.length; i++) {
            _addMember(
                members_[i],
                shares_[i],
                votingRight_[i],
                nonVotingShare_[i],
                mixShare_[i],
                minShare_[i]
            );
        }
        emit ContractCreated(unlockTime, totalShare);
    }

    function reward(address target, uint32 amount) public {
        /// @dev rely on ^0.8.0 over/under flow check. not gas efficient but too lazy for early revert.

        require(block.timestamp < unlockTime, "time out");

        // use up voting right
        if (amount > shares[msg.sender].votingRight) {
            shares[msg.sender].share -= (amount -
                shares[msg.sender].votingRight);

            totalShare -= amount - shares[msg.sender].votingRight;

            shares[msg.sender].votingRight = 0;
        } else {
            shares[msg.sender].votingRight -= amount;
        }

        shares[target].nonVotingShare += amount;
        totalShare += amount;

        verifyShare(msg.sender);
        verifyShare(target);
    }

    function punish(address target, uint32 amount) public {
        /// @dev rely on ^0.8.0 over/under flow check. not gas efficient but too lazy for early revert.
        require(block.timestamp < unlockTime, "time out");

        // use up voting right
        if (amount > shares[msg.sender].votingRight) {
            shares[msg.sender].share -= amount - shares[msg.sender].votingRight;
            totalShare -= amount - shares[msg.sender].votingRight;

            shares[msg.sender].votingRight = 0;
        } else {
            shares[msg.sender].votingRight -= amount;
        }

        if (amount > shares[target].nonVotingShare) {
            shares[target].share -= (amount - shares[target].nonVotingShare);
            shares[target].nonVotingShare = 0;
        } else {
            shares[target].nonVotingShare -= amount;
        }

        totalShare -= amount;

        verifyShare(msg.sender);
        verifyShare(target);
    }

    /**
     * @dev The Ether received will be logged with {PaymentReceived} events. Note that these events are not fully
     * reliable: it's possible for a contract to receive Ether without triggering this function. This only affects the
     * reliability of the events, and not the actual splitting of Ether.
     *
     * To learn more about this see the Solidity documentation for
     * https://solidity.readthedocs.io/en/latest/contracts.html#fallback-function[fallback
     * functions].
     */
    receive() external payable virtual {
        emit PaymentReceived(_msgSender(), msg.value);
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of Ether they are owed, according to their percentage of the
     * total shares and their previous withdrawals.
     */
    function release(address payable account) public virtual {
        require(block.timestamp > unlockTime, "not unlock yet");

        require(
            shares[account].share + shares[account].nonVotingShare > 0,
            "no share"
        );
        uint256 totalReceived = address(this).balance + totalReleased;
        uint256 payment = _pendingPayment(
            account,
            totalReceived,
            released[account]
        );

        require(payment != 0, "no pending");

        released[account] += payment;
        totalReleased += payment;

        AddressUpgradeable.sendValue(account, payment);
        emit PaymentReleased(account, payment);
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of `token` tokens they are owed, according to their
     * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
     * contract.
     */
    function release(IERC20Upgradeable token, address account) public virtual {
        require(block.timestamp > unlockTime, "not unlock yet");

        require(
            shares[account].share + shares[account].nonVotingShare > 0,
            "no share"
        );

        uint256 totalReceived = token.balanceOf(address(this)) +
            erc20TotalReleased[token];

        uint256 payment = _pendingPayment(
            account,
            totalReceived,
            erc20Released[token][account]
        );

        require(payment != 0, "no pending");

        erc20Released[token][account] += payment;
        erc20TotalReleased[token] += payment;

        SafeERC20Upgradeable.safeTransfer(token, account, payment);
        emit ERC20PaymentReleased(token, account, payment);
    }

    /**
     * @dev internal logic for computing the pending payment of an `account` given the token historical balances and
     * already released amounts.
     */
    function _pendingPayment(
        address account,
        uint256 totalReceived,
        uint256 alreadyReleased
    ) private view returns (uint256) {
        return
            (totalReceived *
                (shares[account].share + shares[account].nonVotingShare)) /
            totalShare -
            alreadyReleased;
    }

    /**
     * @dev Add a new payee to the contract.
     * @param account The address of the payee to add.
     * @param shares_ The number of shares owned by the payee.
     */
    function _addMember(
        address account,
        uint32 shares_,
        uint32 votingRight_,
        uint32 nonVotingShare_,
        uint32 mixShare_,
        uint32 minShare_
    ) private {
        /// @dev we allow burn. - simply assign share to address 0 <- not recommended. maybe send to yoyoismee.eth instate.

        members.push(account);
        shares[account] = Share({
            share: shares_,
            votingRight: votingRight_,
            nonVotingShare: nonVotingShare_,
            maxShare: mixShare_,
            minShare: minShare_
        });

        verifyShare(account);
        totalShare += shares_ + nonVotingShare_;

        emit MemberAdded(
            account,
            shares_,
            votingRight_,
            nonVotingShare_,
            mixShare_,
            minShare_
        );
    }

    function verifyShare(address wallet) internal view {
        require(
            shares[wallet].share + shares[wallet].nonVotingShare >=
                shares[wallet].minShare,
            "min share"
        );
        require(
            shares[wallet].share + shares[wallet].nonVotingShare <=
                shares[wallet].maxShare,
            "max share"
        );
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[43] private __gap;
}
