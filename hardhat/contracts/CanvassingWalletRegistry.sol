// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title CanvassingWalletRegistry
 * @author Canvassing
 * @notice A generic, project-agnostic on-chain registry that logs EO (externally-owned)
 *         wallet addresses against opaque user identifiers (UIDs).
 *
 * @dev The contract makes no assumptions about what a UID represents. Any project
 *      that needs to associate a wallet address with a user identity string can
 *      deploy and use this registry. For example:
 *        - Pax (by Canvassing): uid == participantId (Firebase Auth UID)
 *        - Another app: uid == database primary key, username, DID, etc.
 *
 *      UIDs are never stored or emitted in plain text. They are always hashed
 *      via keccak256 before touching the chain, so a UID leak off-chain cannot
 *      be used to deanonymise a wallet address on-chain.
 *
 *      Callers verify membership off-chain by hashing the known UID and checking
 *      isUidHashLogged or uidHashByWallet themselves.
 *
 *      Implements the UUPS upgradeable proxy pattern.
 *      Owned by the deployer; only the owner may log wallets or authorise upgrades.
 */
contract CanvassingWalletRegistry is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /**
     * @notice Semantic version of the running implementation.
     * @dev Incremented on every upgrade so consumers can detect which version is live.
     */
    uint256 public version;

    /**
     * @notice Total number of wallet entries logged across all users.
     */
    uint256 public totalWalletsLogged;

    /**
     * @notice Maps a sequential index (0-based) to the EO wallet address logged at that position.
     */
    mapping(uint256 => address) public walletByIndex;

    /**
     * @notice Maps an EO wallet address to the keccak256 hash of the UID it belongs to.
     * @dev The raw UID is never stored on-chain. To verify off-chain:
     *      keccak256(abi.encodePacked(uid)) == uidHashByWallet[eoAddress]
     */
    mapping(address => bytes32) public uidHashByWallet;

    /**
     * @notice Returns true if a UID hash has already been logged.
     * @dev Prevents the same user from registering more than one wallet.
     *      Check off-chain: isUidHashLogged[keccak256(abi.encodePacked(uid))]
     */
    mapping(bytes32 => bool) public isUidHashLogged;

    /**
     * @notice Returns true if an EO wallet address has already been logged.
     * @dev Prevents duplicate entries for the same wallet address.
     */
    mapping(address => bool) public isWalletLogged;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted when a new EO wallet is successfully logged.
     * @param index     The zero-based position of this wallet in the registry.
     * @param eoAddress The EO wallet address that was logged.
     * @param uidHash   The keccak256 hash of the UID — the raw UID is never emitted.
     */
    event WalletLogged(
        uint256 indexed index,
        address indexed eoAddress,
        bytes32 indexed uidHash
    );

    /**
     * @notice Emitted when the contract implementation is upgraded.
     * @param oldVersion        The version before the upgrade.
     * @param newVersion        The version after the upgrade.
     * @param newImplementation The address of the new implementation contract.
     */
    event ContractUpgraded(
        uint256 oldVersion,
        uint256 newVersion,
        address indexed newImplementation
    );

    // -------------------------------------------------------------------------
    // Constructor / Initializer
    // -------------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialises the proxy. Called once at deployment time.
     * @param _owner The address that will own and administer this contract.
     */
    function initialize(address _owner) public initializer {
        require(_owner != address(0), "CanvassingWalletRegistry: owner cannot be zero address");

        __Ownable_init(_owner);

        version = 1;
    }

    // -------------------------------------------------------------------------
    // Core logic
    // -------------------------------------------------------------------------

    /**
     * @notice Log a newly created EO wallet address against a user UID.
     * @dev Only callable by the contract owner.
     *      Reverts if the wallet or UID has already been logged.
     *
     *      The UID is hashed with keccak256 before any state is written or
     *      events are emitted. The raw UID never touches the chain.
     *
     * @param eoAddress The EO wallet address to register.
     * @param uid       The raw opaque identifier for the user who owns this wallet.
     *                  For Pax this is the Firebase UID (participantId); other
     *                  projects may pass any unique user identifier they choose.
     *                  It is hashed on-chain and never stored in plain text.
     */
    function logWallet(
        address eoAddress,
        string calldata uid
    ) external onlyOwner {
        require(eoAddress != address(0), "CanvassingWalletRegistry: eoAddress cannot be zero address");
        require(bytes(uid).length > 0, "CanvassingWalletRegistry: uid cannot be empty");
        require(!isWalletLogged[eoAddress], "CanvassingWalletRegistry: wallet already logged");

        bytes32 uidHash = keccak256(abi.encodePacked(uid));

        require(!isUidHashLogged[uidHash], "CanvassingWalletRegistry: uid already logged");

        uint256 index = totalWalletsLogged;

        walletByIndex[index] = eoAddress;
        uidHashByWallet[eoAddress] = uidHash;
        isWalletLogged[eoAddress] = true;
        isUidHashLogged[uidHash] = true;

        totalWalletsLogged++;

        emit WalletLogged(index, eoAddress, uidHash);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Look up the UID hash associated with a given EO wallet address.
     * @param eoAddress The wallet address to query.
     * @return The keccak256 hash of the UID, or bytes32(0) if not registered.
     */
    function getUidHash(address eoAddress) external view returns (bytes32) {
        return uidHashByWallet[eoAddress];
    }

    /**
     * @notice Verify whether a raw UID is associated with a given EO wallet address.
     * @dev Hashes the supplied UID and compares it against the stored hash.
     *      Useful for off-chain callers that already know the UID and want a
     *      single on-chain confirmation call.
     * @param eoAddress The wallet address to check.
     * @param uid       The raw UID to verify against.
     * @return True if the hash of `uid` matches the stored hash for `eoAddress`.
     */
    function verifyWalletOwner(
        address eoAddress,
        string calldata uid
    ) external view returns (bool) {
        return uidHashByWallet[eoAddress] == keccak256(abi.encodePacked(uid));
    }

    /**
     * @notice Retrieve a paginated slice of logged wallet addresses.
     * @param startIndex Inclusive start index (0-based).
     * @param endIndex   Exclusive end index. Clamped to `totalWalletsLogged`.
     * @return addresses An ordered array of EO wallet addresses in the requested range.
     */
    function getWallets(
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (address[] memory addresses) {
        uint256 cap = endIndex > totalWalletsLogged ? totalWalletsLogged : endIndex;
        require(startIndex < cap, "CanvassingWalletRegistry: invalid range");

        uint256 length = cap - startIndex;
        addresses = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            addresses[i] = walletByIndex[startIndex + i];
        }
    }

    // -------------------------------------------------------------------------
    // Upgrade mechanics
    // -------------------------------------------------------------------------

    /**
     * @notice Upgrade to a new implementation and record the new version number.
     * @dev The caller must supply a version strictly greater than the current one,
     *      ensuring the on-chain version always moves forward.
     * @param newImplementation Address of the new implementation contract.
     * @param newVersion        Version number for the new implementation.
     */
    function upgradeToAndBumpVersion(
        address newImplementation,
        uint256 newVersion
    ) external onlyOwner {
        require(
            newVersion > version,
            "CanvassingWalletRegistry: newVersion must be greater than current version"
        );

        uint256 oldVersion = version;
        version = newVersion;

        upgradeToAndCall(newImplementation, new bytes(0));

        emit ContractUpgraded(oldVersion, newVersion, newImplementation);
    }

    /**
     * @notice Required UUPS override — only the owner may authorise an upgrade.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    // -------------------------------------------------------------------------
    // Storage gap
    // -------------------------------------------------------------------------

    /**
     * @dev Reserved space to allow future versions to add state variables
     *      without corrupting the storage layout of upgraded contracts.
     */
    uint256[50] private __gap;
}

