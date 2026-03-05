// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title CanvassingTaskManager
 * @author Canvassing
 * @notice Manages participant screening across all tasks. Holds no token value —
 *         purely a data contract. Calls are made by smart account wallets via
 *         paymaster-sponsored transactions.
 *
 * @dev Single upgradeable deployment. All task state is namespaced by `taskId`.
 *      Backend signature (EIP-712) is the source of truth for screening eligibility.
 *      One screening per `smartAccountContractAddress` per `taskId` is enforced.
 *
 *      Since transactions are paymaster-sponsored, msg.sender is the smart account
 *      (proxy wallet), not the EOA. This mirrors the pattern in TaskManagerV3 where
 *      msg.sender == participantProxy.
 *
 *      Implements UUPS upgradeable proxy pattern.
 */
contract CanvassingTaskManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable
{
    using ECDSA for bytes32;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev EIP-712 typehash for screening requests.
    bytes32 private constant SCREENING_REQUEST_TYPEHASH =
        keccak256(
            "ScreeningRequest(address smartAccountContractAddress,string taskId,uint256 nonce)"
        );

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /**
     * @notice Semantic version of the running implementation.
     */
    uint256 public version;

    /**
     * @notice Address of the backend signer that authorises screening requests.
     */
    address public signer;

    /**
     * @notice Returns true if a smartAccountContractAddress has been screened for a given taskId.
     * @dev Key: keccak256(abi.encodePacked(taskId, smartAccountContractAddress))
     */
    mapping(bytes32 => bool) public isScreened;

    /**
     * @notice Returns true if a screening signature has already been used.
     * @dev Prevents replay attacks.
     */
    mapping(bytes => bool) public isScreeningSignatureUsed;

    /**
     * @notice Total number of screenings processed across all tasks.
     */
    uint256 public totalScreenings;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted when a participant proxy is successfully screened for a task.
     * @param smartAccountContractAddress The smart account address of the participant.
     * @param taskId                      The task the participant was screened for.
     */
    event ParticipantProxyScreened(
        address indexed smartAccountContractAddress,
        string taskId
    );

    /**
     * @notice Emitted when the signer address is updated.
     * @param oldSigner The previous signer address.
     * @param newSigner The new signer address.
     */
    event SignerUpdated(
        address indexed oldSigner,
        address indexed newSigner
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
     * @param _owner  The address that will own and administer this contract.
     * @param _signer The backend signer address that authorises screenings.
     */
    function initialize(
        address _owner,
        address _signer
    ) public initializer {
        require(_owner != address(0), "CanvassingTaskManager: owner cannot be zero address");
        require(_signer != address(0), "CanvassingTaskManager: signer cannot be zero address");

        __Ownable_init(_owner);
        __Pausable_init();
        __EIP712_init("CanvassingTaskManager", "1");

        signer = _signer;
        version = 1;
    }

    // -------------------------------------------------------------------------
    // Core logic
    // -------------------------------------------------------------------------

    /**
     * @notice Screen a participant proxy for a task.
     * @dev Called by the participant's smart account wallet via a paymaster-sponsored
     *      transaction. msg.sender must match `smartAccountContractAddress`, mirroring
     *      the TaskManagerV3 pattern where msg.sender == participantProxy.
     *
     *      Reverts if already screened for this task, or if the signature is invalid
     *      or has already been used.
     *
     * @param smartAccountContractAddress The smart account address of the participant (must be msg.sender).
     * @param taskId                      The unique identifier of the task being screened for.
     * @param nonce                       A unique number to prevent signature replay.
     * @param signature                   EIP-712 signature from the backend signer.
     */
    function screenParticipantProxy(
        address smartAccountContractAddress,
        string calldata taskId,
        uint256 nonce,
        bytes calldata signature
    ) external whenNotPaused {
        require(
            msg.sender == smartAccountContractAddress,
            "CanvassingTaskManager: sender must be smartAccountContractAddress"
        );
        require(
            smartAccountContractAddress != address(0),
            "CanvassingTaskManager: smartAccountContractAddress cannot be zero address"
        );
        require(bytes(taskId).length > 0, "CanvassingTaskManager: taskId cannot be empty");

        bytes32 slot = _slot(taskId, smartAccountContractAddress);
        require(!isScreened[slot], "CanvassingTaskManager: already screened for this task");
        require(!isScreeningSignatureUsed[signature], "CanvassingTaskManager: signature already used");

        require(
            _verifyScreeningSignature(smartAccountContractAddress, taskId, nonce, signature),
            "CanvassingTaskManager: invalid signature"
        );

        isScreened[slot] = true;
        isScreeningSignatureUsed[signature] = true;

        unchecked { ++totalScreenings; }

        emit ParticipantProxyScreened(smartAccountContractAddress, taskId);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Check whether a smartAccountContractAddress has been screened for a given taskId.
     * @param taskId                      The task identifier.
     * @param smartAccountContractAddress The smart account address to check.
     * @return True if screened.
     */
    function checkIfScreened(
        string calldata taskId,
        address smartAccountContractAddress
    ) external view returns (bool) {
        return isScreened[_slot(taskId, smartAccountContractAddress)];
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /**
     * @notice Update the backend signer address.
     * @param newSigner The new signer address.
     */
    function setSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "CanvassingTaskManager: signer cannot be zero address");
        address oldSigner = signer;
        signer = newSigner;
        emit SignerUpdated(oldSigner, newSigner);
    }

    /**
     * @notice Pause all screening operations.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resume all screening operations.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Derives the storage slot key for a (taskId, smartAccountContractAddress) pair.
     */
    function _slot(
        string calldata taskId,
        address smartAccountContractAddress
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(taskId, smartAccountContractAddress));
    }

    /**
     * @dev Verifies an EIP-712 screening signature against the stored signer.
     */
    function _verifyScreeningSignature(
        address smartAccountContractAddress,
        string calldata taskId,
        uint256 nonce,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SCREENING_REQUEST_TYPEHASH,
                    smartAccountContractAddress,
                    keccak256(bytes(taskId)),
                    nonce
                )
            )
        );
        return ECDSA.recover(digest, signature) == signer;
    }

    // -------------------------------------------------------------------------
    // Upgrade mechanics
    // -------------------------------------------------------------------------

    /**
     * @notice Upgrade to a new implementation and record the new version number.
     * @param newImplementation Address of the new implementation contract.
     * @param newVersion        Version number for the new implementation (must be > current).
     */
    function upgradeToAndBumpVersion(
        address newImplementation,
        uint256 newVersion
    ) external onlyOwner {
        require(
            newVersion > version,
            "CanvassingTaskManager: newVersion must be greater than current version"
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

    uint256[50] private __gap;
}

