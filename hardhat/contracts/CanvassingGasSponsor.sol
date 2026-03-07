// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./CanvassingWalletRegistry.sol";

/**
 * @title CanvassingGasSponsor
 * @author Canvassing
 * @notice Sends native gas token (CELO) to wallet addresses that are registered
 *         in a deployed CanvassingWalletRegistry instance.
 *
 * @dev Only the contract owner may trigger sponsorships. The contract must be
 *      funded manually by sending CELO to it. Sponsorship is gated by the
 *      registry — only wallets that have been logged via CanvassingWalletRegistry
 *      can receive gas.
 *
 *      Implements the UUPS upgradeable proxy pattern.
 *      Owned by the deployer; only the owner may sponsor wallets or authorise upgrades.
 */
contract CanvassingGasSponsor is
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
     * @notice The CanvassingWalletRegistry instance this contract is coupled to.
     * @dev Only wallets registered in this registry may receive gas sponsorships.
     */
    CanvassingWalletRegistry public registry;

    /**
     * @notice Total amount of CELO (in wei) that has been sponsored across all wallets.
     */
    uint256 public totalCeloSponsored;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted when CELO is successfully sent to a registered wallet.
     * @param eoAddress The wallet address that received the CELO.
     * @param amount    The amount of CELO sent, in wei.
     */
    event WalletSponsored(
        address indexed eoAddress,
        uint256 amount
    );

    /**
     * @notice Emitted when the registry address is updated.
     * @param oldRegistry The previous registry address.
     * @param newRegistry The new registry address.
     */
    event RegistryUpdated(
        address indexed oldRegistry,
        address indexed newRegistry
    );

    /**
     * @notice Emitted when CELO is deposited into this contract.
     * @param sender The address that sent the CELO.
     * @param amount The amount of CELO deposited, in wei.
     */
    event Funded(
        address indexed sender,
        uint256 amount
    );

    /**
     * @notice Emitted when the owner withdraws CELO from this contract.
     * @param to     The address that received the withdrawn CELO.
     * @param amount The amount of CELO withdrawn, in wei.
     */
    event Withdrawn(
        address indexed to,
        uint256 amount
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
     * @param _owner    The address that will own and administer this contract.
     * @param _registry The address of the deployed CanvassingWalletRegistry.
     */
    function initialize(
        address _owner,
        address _registry
    ) public initializer {
        require(_owner != address(0), "CanvassingGasSponsor: owner cannot be zero address");
        require(_registry != address(0), "CanvassingGasSponsor: registry cannot be zero address");

        __Ownable_init(_owner);

        registry = CanvassingWalletRegistry(_registry);
        version = 1;
    }

    // -------------------------------------------------------------------------
    // Funding
    // -------------------------------------------------------------------------

    /**
     * @notice Accept incoming CELO deposits.
     */
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    // -------------------------------------------------------------------------
    // Core logic
    // -------------------------------------------------------------------------

    /**
     * @notice Send CELO to a registered wallet address.
     * @dev Only callable by the contract owner.
     *      Reverts if the wallet is not registered in the coupled registry.
     *      Reverts if the contract does not have sufficient CELO balance.
     * @param eoAddress The registered EO wallet address to sponsor.
     * @param amount    The amount of CELO to send, in wei.
     */
    function sponsorWallet(
        address eoAddress,
        uint256 amount
    ) external onlyOwner {
        require(eoAddress != address(0), "CanvassingGasSponsor: eoAddress cannot be zero address");
        require(amount > 0, "CanvassingGasSponsor: amount must be greater than zero");
        require(
            registry.isWalletLogged(eoAddress),
            "CanvassingGasSponsor: wallet not registered in registry"
        );
        require(
            address(this).balance >= amount,
            "CanvassingGasSponsor: insufficient CELO balance"
        );

        totalCeloSponsored += amount;

        (bool success, ) = eoAddress.call{value: amount}("");
        require(success, "CanvassingGasSponsor: CELO transfer failed");

        emit WalletSponsored(eoAddress, amount);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /**
     * @notice Update the registry this contract is coupled to.
     * @dev Useful if a new CanvassingWalletRegistry is deployed.
     * @param newRegistry The address of the new CanvassingWalletRegistry.
     */
    function setRegistry(address newRegistry) external onlyOwner {
        require(newRegistry != address(0), "CanvassingGasSponsor: registry cannot be zero address");

        address oldRegistry = address(registry);
        registry = CanvassingWalletRegistry(newRegistry);

        emit RegistryUpdated(oldRegistry, newRegistry);
    }

    /**
     * @notice Withdraw CELO from the contract back to a specified address.
     * @dev Only callable by the owner. Useful for recovering funds or rebalancing.
     * @param to     The address to send the CELO to.
     * @param amount The amount of CELO to withdraw, in wei.
     */
    function withdraw(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "CanvassingGasSponsor: recipient cannot be zero address");
        require(amount > 0, "CanvassingGasSponsor: amount must be greater than zero");
        require(address(this).balance >= amount, "CanvassingGasSponsor: insufficient balance");

        (bool success, ) = to.call{value: amount}("");
        require(success, "CanvassingGasSponsor: withdrawal failed");

        emit Withdrawn(to, amount);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the current CELO balance held by this contract.
     * @return The balance in wei.
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // -------------------------------------------------------------------------
    // Upgrade mechanics
    // -------------------------------------------------------------------------

    /**
     * @notice Upgrade to a new implementation and record the new version number.
     * @dev The caller must supply a version strictly greater than the current one.
     * @param newImplementation Address of the new implementation contract.
     * @param newVersion        Version number for the new implementation.
     */
    function upgradeToAndBumpVersion(
        address newImplementation,
        uint256 newVersion
    ) external onlyOwner {
        require(
            newVersion > version,
            "CanvassingGasSponsor: newVersion must be greater than current version"
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

