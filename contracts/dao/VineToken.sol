// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../interfaces/IERC2612.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../dependencies/VineOwnable.sol";

/**
    @title Vine Governance Token
    @notice Given as an incentive for users of the protocol. Can be locked in `TokenLocker`
            to receive lock weight, which gives governance power within the Vine DAO.
 */
contract VineToken is ERC20, IERC2612, VineOwnable {
    // --- ERC20 Data ---

    string internal constant _NAME = "Vine Governance Token";
    string internal constant _SYMBOL = "VINE";
    string public constant version = "1";

    // --- EIP 2612 Data ---

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant permitTypeHash = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _TYPE_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // Cache the domain separator as an immutable value, but also store the chain id that it
    // corresponds to, in order to invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;

    address public locker;
    address public vault;
    address public celerEndPoint;

    uint256 public maxTotalSupply;

    mapping(address => uint256) private _nonces;

    event ReceiveFromChain(uint16 indexed _srcChainId, address indexed _to, uint256 _amount);
    event SendToChain(uint16 indexed _dstChainId, address indexed _from, bytes _toAddress, uint256 _amount);

    // --- Functions ---

    constructor(address _vineCore) ERC20(_NAME, _SYMBOL) VineOwnable(_vineCore) {
        bytes32 hashedName = keccak256(bytes(_NAME));
        bytes32 hashedVersion = keccak256(bytes(version));

        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(_TYPE_HASH, hashedName, hashedVersion);
    }

    function setInitialParameters(address _vault, address _locker) external {
        require(vault == address(0) && _vault != address(0));
        vault = _vault;
        locker = _locker;
    }

    function setCelerEndPoint(address _celer) external onlyOwner {
        celerEndPoint = _celer;
    }

    function mintToVault(uint256 _totalSupply) external returns (bool) {
        require(msg.sender == vault);
        require(maxTotalSupply == 0);

        _mint(vault, _totalSupply);
        maxTotalSupply = _totalSupply;

        return true;
    }

    function receiveFromChain(uint16 srcChainId, address account, uint256 amount) external {
        require(msg.sender == celerEndPoint, "Vine: Caller not CE");
        _mint(account, amount);
        emit ReceiveFromChain(srcChainId, account, amount);
    }

    function burn(uint16 dstChainId, address from, bytes memory to, uint256 amount) external {
        require(msg.sender == celerEndPoint, "Vine: Caller not CE");
        _burn(from, amount);
        emit SendToChain(dstChainId, from, to, amount);
    }

    // --- EIP 2612 functionality ---

    function domainSeparator() public view override returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(deadline >= block.timestamp, "VINE: expired deadline");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator(),
                keccak256(abi.encode(permitTypeHash, owner, spender, amount, _nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress == owner, "VINE: invalid signature");
        _approve(owner, spender, amount);
    }

    function nonces(address owner) external view override returns (uint256) {
        // FOR EIP 2612
        return _nonces[owner];
    }

    function transferToLocker(address sender, uint256 amount) external returns (bool) {
        require(msg.sender == locker, "Not locker");
        _transfer(sender, locker, amount);
        return true;
    }

    // --- Internal operations ---

    function _buildDomainSeparator(bytes32 typeHash, bytes32 name_, bytes32 version_) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, name_, version_, block.chainid, address(this)));
    }
}
