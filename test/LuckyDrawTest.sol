// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import "../src/LuckyDraw.sol";
import "./Utilities.sol";

contract LuckyDrawTest is Utilities {
    Utilities internal utils = new Utilities();

    address payable[] internal users = utils.createUsers(40);

    address internal immutable addr = users[0];
    address internal immutable addr1 = users[1];
    address internal immutable addr2 = users[2];

    bytes32 internal constant keyHash =
        0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;

    uint64 internal initialSubscriptionId;
    VRFCoordinatorV2Mock internal vrfCoordinatorV2Mock;
    LuckyDraw internal luckyDraw;

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

    function setUp() public {
        skip(10);

        vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock(
            100000, // base fee
            100000 // gas price link
        );
        luckyDraw = new LuckyDraw(address(vrfCoordinatorV2Mock), keyHash);

        initialSubscriptionId = vrfCoordinatorV2Mock.createSubscription();
        luckyDraw.safeMint(addr, 10);

        vm.prank(addr);
        luckyDraw.createLuckyDraw(1, initialSubscriptionId);
        // add 20 participants from users[1] to users[21] to the lucky draw of the nft of the token id 1
        for (uint256 i = 1; i < 21; i++) {
            vm.prank(users[i]);
            luckyDraw.registerParticipant(1);
        }
        vm.stopPrank();
    }

    function testOwner() public {
        assertEq(luckyDraw.owner(), address(this));
    }

    function testPublicConstantVariables() public {
        assertEq(
            address(luckyDraw.COORDINATOR()),
            address(vrfCoordinatorV2Mock)
        );
        assertEq(luckyDraw.KEY_HASH(), keyHash);
        assertTrue(luckyDraw.isLuckDrawActive(1));
        assertEq(luckyDraw.tokenIdToSubscriptionId(1), initialSubscriptionId);
    }

    // pay attention that 20 nfts were minted to addr initially
    function testSafeMintSuccess() public {
        vm.expectEmit(true, true, true, true);
        emit Mint(addr, 20);
        luckyDraw.safeMint(addr, 20);

        assertEq(luckyDraw.balanceOf(addr), 30);
        assertEq(luckyDraw.ownerOf(0), addr);
        assertEq(luckyDraw.ownerOf(29), addr);

        vm.expectEmit(true, true, true, true);
        emit Mint(addr2, 40);
        luckyDraw.safeMint(addr2, 40);

        assertEq(luckyDraw.balanceOf(addr2), 40);
        assertEq(luckyDraw.ownerOf(30), addr2);
        assertEq(luckyDraw.ownerOf(69), addr2);
    }

    function testSafeMintRevert() public {
        vm.prank(addr);
        vm.expectRevert("Ownable: caller is not the owner");
        luckyDraw.safeMint(addr, 10);

        vm.expectRevert("Cannot mint 0 NFT");
        luckyDraw.safeMint(addr1, 0);
    }

    function testCreateLuckyDrawSuccess() public {
        // test initital lucky draw for nft with id 1
        assertTrue(luckyDraw.isLuckDrawActive(1));
        assertEq(luckyDraw.tokenIdToSubscriptionId(1), initialSubscriptionId);

        // test new lucky draw creation for nft with id 15
        luckyDraw.safeMint(addr2, 10);

        vm.prank(addr2);

        vm.expectEmit(true, true, true, true);
        emit LuckyDrawCreated(15, initialSubscriptionId);
        luckyDraw.createLuckyDraw(15, initialSubscriptionId);

        assertTrue(luckyDraw.isLuckDrawActive(15));
        assertEq(luckyDraw.tokenIdToSubscriptionId(15), initialSubscriptionId);
    }

    function testCreateLuckyDrawRevert() public {
        // create lucky draw from the initial subscription
        vm.expectRevert("Caller is not the token owner nor approved");
        luckyDraw.createLuckyDraw(5, initialSubscriptionId);

        // set up new subscription
        vm.startPrank(addr);
        uint64 subscriptionId = vrfCoordinatorV2Mock.createSubscription();
        vrfCoordinatorV2Mock.fundSubscription(subscriptionId, 100e18);
        vm.stopPrank();

        vm.expectRevert("Lucky draw for this token has already been created");
        vm.prank(addr);
        luckyDraw.createLuckyDraw(1, subscriptionId);
    }

    function testChangeLuckyDrawStatusSuccess() public {
        vm.startPrank(addr);

        luckyDraw.changeLuckDrawStatus(1);
        assertFalse(luckyDraw.isLuckDrawActive(1));
        luckyDraw.changeLuckDrawStatus(1);
        assertTrue(luckyDraw.isLuckDrawActive(1));

        vm.stopPrank();
    }

    function testChangeLuckyDrawStatusRevert() public {
        vm.expectRevert("Caller is not the token owner nor approved");
        luckyDraw.changeLuckDrawStatus(1);
    }

    function testRegisterParticipantSuccess() public {
        // add users25 as participant 20th to the lucky draw of the nft of the token id 1
        vm.prank(users[25]);

        vm.expectEmit(true, true, true, true);
        emit ParticipantRegistered(1, users[25]);
        luckyDraw.registerParticipant(1);
        assertEq(luckyDraw.tokenIdToParticipants(1, 20), users[25]);

        // test adding participants for the new lucky draw of the nft of the token id 8
        vm.prank(addr);
        luckyDraw.createLuckyDraw(8, initialSubscriptionId);

        vm.prank(users[35]);

        vm.expectEmit(true, true, true, true);
        emit ParticipantRegistered(8, users[35]);
        luckyDraw.registerParticipant(8);
        assertEq(luckyDraw.tokenIdToParticipants(8, 0), users[35]);
    }

    function testRegisterParticipantRevert() public {
        // revert when the lucky draw is not active
        vm.prank(users[25]);
        vm.expectRevert("Lucky draw is not active");
        luckyDraw.registerParticipant(3);

        // also revert when the nft is not minted yet
        vm.expectRevert("Lucky draw is not active");
        luckyDraw.registerParticipant(30);

        vm.expectRevert("You already registered");
        vm.prank(addr1);
        luckyDraw.registerParticipant(1);
    }

    function testMakeDrawSuccess() public {
        // fund the subscription and add LuckyDraw contract as a consumer
        vrfCoordinatorV2Mock.fundSubscription(initialSubscriptionId, 10e18);
        vrfCoordinatorV2Mock.addConsumer(
            initialSubscriptionId,
            address(luckyDraw)
        );

        skip(200);
        vm.startPrank(addr);
        uint256 requestId = luckyDraw.makeDraw(1);
        skip(1000000);
        vm.stopPrank();

        console.log(luckyDraw.requestedIdToTokenId(requestId));

        // wait for the contract to finish fulfillRandomWords() callback. How? :<
        // while (luckyDraw.DRAW_IN_PROGRESS() == true) {} // failed, out of gas

        // console.log(luckyDraw.requestedIdToTokenId(requestId));
    }

    function testMakeDrawRevert() public {
        // fund the subscription and add LuckyDraw contract as a consumer
        vrfCoordinatorV2Mock.fundSubscription(initialSubscriptionId, 10e18);
        vrfCoordinatorV2Mock.addConsumer(
            initialSubscriptionId,
            address(luckyDraw)
        );

        vm.prank(addr);
        luckyDraw.createLuckyDraw(3, initialSubscriptionId);
        vm.prank(addr2);
        luckyDraw.registerParticipant(3);
        vm.expectRevert("Not enough participants to make a draw");
        vm.prank(addr);
        luckyDraw.makeDraw(3);

        vm.prank(addr);
        luckyDraw.makeDraw(1);
        vm.expectRevert("Lucky draw in progress");
        luckyDraw.makeDraw(1);
    }
}
