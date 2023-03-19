// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract LuckyDraw is ERC721, ERC721Holder, VRFConsumerBaseV2, Ownable {
    uint256 private _tokenIdCounter;
    uint32 private constant CALLBACK_GAS_LIMIT = 100000;
    uint8 private constant REQUEST_CONFIRMATIONS = 3;
    uint8 private constant NUM_WORDS = 1;

    VRFCoordinatorV2Interface public immutable COORDINATOR;
    bytes32 public immutable KEY_HASH;
    bool public DRAW_IN_PROGRESS;

    event Mint(address indexed to, uint256 indexed amount);
    event LuckyDrawCreated(
        uint256 indexed tokenId,
        uint256 indexed subscriptionId
    );
    event ParticipantRegistered(uint256 tokenId, address participant);
    event DrawResult(
        uint256 indexed tokenId,
        uint256 requestId,
        uint256 indexed randomWord,
        uint256 winnerIndex,
        address indexed winner
    );

    modifier isApprovedOrOwner(uint256 tokenId) {
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "Caller is not the token owner nor approved"
        );
        _;
    }

    mapping(uint256 => bool) public isLuckDrawActive;
    mapping(uint256 => uint64) public tokenIdToSubscriptionId;
    mapping(uint256 => address[]) public tokenIdToParticipants;
    mapping(uint256 => uint256) public requestedIdToTokenId;
    mapping(uint256 => address) public tokenIdToWinner;

    // mapping(uint256 => uint256) public tokenId

    constructor(
        address vrfCoordinatorAddress,
        bytes32 keyHash
    ) ERC721("LuckyToken", "LKT") VRFConsumerBaseV2(vrfCoordinatorAddress) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinatorAddress);
        KEY_HASH = keyHash;
    }

    function safeMint(address to, uint256 amount) public onlyOwner {
        require(amount > 0, "Cannot mint 0 NFT");

        for (uint256 i = 0; i < amount; ) {
            uint256 tokenId = _tokenIdCounter;
            unchecked {
                ++_tokenIdCounter;
                ++i;
            }
            _safeMint(to, tokenId);
        }

        emit Mint(to, amount);
    }

    function claimReward(uint256 tokenId) public {
        require(
            msg.sender == tokenIdToWinner[tokenId],
            "Only the winner can claim the reward"
        );

        safeTransferFrom(address(this), msg.sender, tokenId);
        delete tokenIdToWinner[tokenId];
    }

    function createLuckyDraw(
        uint256 tokenId,
        uint64 subscriptionId
    ) public isApprovedOrOwner(tokenId) {
        require(
            tokenIdToSubscriptionId[tokenId] == 0,
            "Lucky draw for this token has already been created"
        );

        isLuckDrawActive[tokenId] = true;
        tokenIdToSubscriptionId[tokenId] = subscriptionId;

        emit LuckyDrawCreated(tokenId, subscriptionId);
    }

    function changeLuckDrawStatus(
        uint256 tokenId
    ) public isApprovedOrOwner(tokenId) {
        isLuckDrawActive[tokenId] = !isLuckDrawActive[tokenId];
    }

    function registerParticipant(uint256 tokenId) public {
        require(isLuckDrawActive[tokenId], "Lucky draw is not active");

        address[] memory participants = tokenIdToParticipants[tokenId];

        for (uint256 i = 0; i < participants.length; ) {
            require(msg.sender != participants[i], "You already registered");
            unchecked {
                ++i;
            }
        }

        tokenIdToParticipants[tokenId].push(msg.sender);

        emit ParticipantRegistered(tokenId, msg.sender);
    }

    function makeDraw(uint256 tokenId) public returns (uint256) {
        // add draw in progress
        uint256 length = tokenIdToParticipants[tokenId].length;

        require(!DRAW_IN_PROGRESS, "Lucky draw in progress");
        require(length > 1, "Not enough participants to make a draw");

        safeTransferFrom(msg.sender, address(this), tokenId);
        DRAW_IN_PROGRESS = true;

        return _requestRandomWord((tokenId));
    }

    function _requestRandomWord(uint256 tokenId) internal returns (uint256) {
        uint256 requestId = COORDINATOR.requestRandomWords(
            KEY_HASH,
            tokenIdToSubscriptionId[tokenId],
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );

        requestedIdToTokenId[requestId] = tokenId;
        return requestId;
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory _randomWords
    ) internal override {
        uint256 tokenId = requestedIdToTokenId[requestId];
        address[] storage participants = tokenIdToParticipants[tokenId];

        // get the winner
        uint256 length = tokenIdToParticipants[tokenId].length;

        uint256 winnerIndex = (_randomWords[0] % length);

        address winner = participants[winnerIndex];

        tokenIdToWinner[tokenId] = winner;

        // Cancel the subscription and send the remaining LINK to a wallet address.
        COORDINATOR.cancelSubscription(
            tokenIdToSubscriptionId[tokenId],
            msg.sender
        );

        // Clear data
        delete tokenIdToParticipants[tokenId];
        delete tokenIdToSubscriptionId[tokenId];
        delete requestedIdToTokenId[tokenId];
        DRAW_IN_PROGRESS = false;

        emit DrawResult(
            tokenId,
            requestId,
            _randomWords[0],
            winnerIndex,
            winner
        );
    }
}
