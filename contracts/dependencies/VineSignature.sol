// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

struct SignatureRSV {
    bytes32 r;
    bytes32 s;
    uint256 v;
}

contract VineSignature {
    bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    string public constant SIGNIN_TYPE = "SignIn(address user,uint32 time)";
    bytes32 public constant SIGNIN_TYPEHASH = keccak256(bytes(SIGNIN_TYPE));
    bytes32 public immutable DOMAIN_SEPARATOR;

    constructor () {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            keccak256("VineSignature.SignIn"),
            keccak256("1"),
            block.chainid,
            address(this)
        ));
    }

    struct SignIn {
        address user;
        uint32 time;
        SignatureRSV rsv;
    }

    modifier authenticated(SignIn calldata auth)
    {
        // Must be signed within 24 hours ago.
        require( auth.time > (block.timestamp - (60*60*24)) );

        // Validate EIP-712 sign-in authentication.
        bytes32 authdataDigest = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                SIGNIN_TYPEHASH,
                auth.user,
                auth.time
            ))
        ));

        address recovered_address = ecrecover(
            authdataDigest, uint8(auth.rsv.v), auth.rsv.r, auth.rsv.s);

        require( auth.user == recovered_address, "Invalid Sign-In" );

        _;
    }
}