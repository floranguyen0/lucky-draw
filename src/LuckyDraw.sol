// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// create withdraw nft
contract LuckyDraw is ERC721, ERC721Holder, VRFConsumerBaseV2, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;
    bool public DRAW_IN_PROGRESS;

    VRFCoordinatorV2Interface public immutable COORDINATOR;
    bytes32 public immutable KEY_HASH;

    uint32 constant CALLBACK_GAS_LIMIT = 100000;
    uint8 constant REQUEST_CONFIRMATIONS = 3;
    uint8 constant NUM_WORDS = 1;

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
            _isApprovedOrOwner(_msgSender(), tokenId),
            "Caller is not the token owner nor approved"
        );
        _;
    }

    modifier isLuckyDrawActive(uint256 tokenId) {
        require(isLuckDrawActive[tokenId], "Lucky draw is not active");
        _;
    }

    mapping(uint256 => bool) public isLuckDrawActive;
    mapping(uint256 => uint64) public tokenIdToSubscriptionId;
    mapping(uint256 => address[]) public tokenIdToParticipants;
    mapping(uint256 => uint256) public requestedIdToTokenId;
    mapping(uint256 => address) public tokenIdToWinner;

    // mapping(uint256 => uint256) public tokenId

    constructor(address vrfCoordinatorAddress, bytes32 keyHash)
        ERC721("LuckyToken", "LKT")
        VRFConsumerBaseV2(vrfCoordinatorAddress)
    {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinatorAddress);
        KEY_HASH = keyHash;
    }

    function safeMint(address to, uint256 amount) public onlyOwner {
        require(amount > 0, "Cannot mint 0 NFT");

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(to, tokenId);
        }

        emit Mint(to, amount);
    }

    function claimReward(uint256 tokenId) public {
        require(
            _msgSender() == tokenIdToWinner[tokenId],
            "Only the winner can claim the reward"
        );

        safeTransferFrom(address(this), _msgSender(), tokenId);
        delete tokenIdToWinner[tokenId];
    }

    function createLuckyDraw(uint256 tokenId, uint64 subscriptionId)
        public
        isApprovedOrOwner(tokenId)
    {
        require(
            tokenIdToSubscriptionId[tokenId] == 0,
            "Lucky draw for this token has already been created"
        );

        isLuckDrawActive[tokenId] = true;
        tokenIdToSubscriptionId[tokenId] = subscriptionId;

        emit LuckyDrawCreated(tokenId, subscriptionId);
    }

    function changeLuckDrawStatus(uint256 tokenId)
        public
        isApprovedOrOwner(tokenId)
    {
        isLuckDrawActive[tokenId] = !isLuckDrawActive[tokenId];
    }

    function registerParticipant(uint256 tokenId)
        public
        isLuckyDrawActive(tokenId)
    {
        address[] memory participants = tokenIdToParticipants[tokenId];

        for (uint256 i = 0; i < participants.length; i++) {
            require(_msgSender() != participants[i], "You already registered");
        }
        tokenIdToParticipants[tokenId].push(_msgSender());

        emit ParticipantRegistered(tokenId, _msgSender());
    }

    function makeDraw(uint256 tokenId) public returns (uint256) {
        // add draw in progress
        address[] memory participants = tokenIdToParticipants[tokenId];

        require(DRAW_IN_PROGRESS == false, "Lucky draw in progress");
        require(
            participants.length > 1,
            "Not enough participants to make a draw"
        );

        safeTransferFrom(_msgSender(), address(this), tokenId);
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
        address[] memory participants = tokenIdToParticipants[tokenId];

        // get the winner
        uint256 participantsLength = participants.length;

        uint256 winnerIndex = (_randomWords[0] % participantsLength);

        address winner = participants[winnerIndex];

        tokenIdToWinner[tokenId] = winner;

        // Cancel the subscription and send the remaining LINK to a wallet address.
        COORDINATOR.cancelSubscription(
            tokenIdToSubscriptionId[tokenId],
            _msgSender()
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
