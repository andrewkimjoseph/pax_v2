// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./CanvassingTaskManager.sol";
import "./CanvassingWalletRegistry.sol";

interface IERC677 {
    function transferAndCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool);
}

/**
 * @title CanvassingRewarder
 * @author Canvassing
 * @notice Handles token reward distribution. Task claims are sponsored (msg.sender = smart account).
 *
 * @dev Single upgradeable deployment. Holds ERC20 token balances for all tasks
 *      and achievements. The reward token and amount are specified in the
 *      backend-signed payload — the contract honours whatever the signature says.
 *
 *      Task reward — single entrypoint claimTaskReward: msg.sender == smartAccountContractAddress
 *      (sponsored userOp). EIP-712 TaskRewardRequest; eoAddress in payload is owner identity (V1 Privy or V2 EOA).
 *      Achievement reward — claimAchievementReward: msg.sender == smartAccountContractAddress
 *      (sponsored userOp). Same EIP-712 pattern; one claim per eoAddress per achievementId.
 *
 *      Tokens are transferred to EIP-712 recipientAddress (e.g. Pax contract for V1;
 *      often same as smartAccountContractAddress for V2). Caller remains the AA.
 *
 *      Implements UUPS upgradeable proxy pattern.
 */
contract CanvassingRewarder is
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

    /// @dev EIP-712 typehash for task reward claims.
    bytes32 private constant TASK_REWARD_TYPEHASH =
        keccak256(
            "TaskRewardRequest(address eoAddress,address smartAccountContractAddress,address recipientAddress,string taskId,address token,uint256 amount,uint256 nonce)"
        );

    /// @dev EIP-712 typehash for achievement reward claims.
    bytes32 private constant ACHIEVEMENT_REWARD_TYPEHASH =
        keccak256(
            "AchievementRewardRequest(address eoAddress,address smartAccountContractAddress,address recipientAddress,string achievementId,address token,uint256 amount,uint256 nonce)"
        );

    /// @dev EIP-712 typehash for referral reward claims.
    bytes32 private constant REFERRAL_REWARD_TYPEHASH =
        keccak256(
            "ReferralRewardRequest(address eoAddress,address referredEoAddress,address smartAccountContractAddress,address recipientAddress,string referralId,address token,uint256 amount,uint256 nonce)"
        );

    /// @dev EIP-712 typehash for task reward claims with donation split.
    bytes32 private constant TASK_REWARD_WITH_DONATION_TYPEHASH =
        keccak256(
            "TaskRewardWithDonationRequest(address eoAddress,address smartAccountContractAddress,address recipientAddress,address donationContractAddress,string taskId,address token,uint256 amount,uint256 donationBasisPoints,uint256 nonce)"
        );

    /// @dev EIP-712 typehash for achievement reward claims with donation split.
    bytes32 private constant ACHIEVEMENT_REWARD_WITH_DONATION_TYPEHASH =
        keccak256(
            "AchievementRewardWithDonationRequest(address eoAddress,address smartAccountContractAddress,address recipientAddress,address donationContractAddress,string achievementId,address token,uint256 amount,uint256 donationBasisPoints,uint256 nonce)"
        );

    /// @dev EIP-712 typehash for referral reward claims with donation split.
    bytes32 private constant REFERRAL_REWARD_WITH_DONATION_TYPEHASH =
        keccak256(
            "ReferralRewardWithDonationRequest(address eoAddress,address referredEoAddress,address smartAccountContractAddress,address recipientAddress,address donationContractAddress,string referralId,address token,uint256 amount,uint256 donationBasisPoints,uint256 nonce)"
        );

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /**
     * @notice Semantic version of the running implementation.
     */
    uint256 public version;

    /**
     * @notice Address of the backend signer that authorises reward claims.
     */
    address public signer;

    /**
     * @notice The CanvassingTaskManager instance used to verify screening status.
     */
    CanvassingTaskManager public taskManager;

    /**
     * @notice The CanvassingWalletRegistry instance used to validate EO wallets.
     * @dev Referral claims are restricted to EO wallets that have been logged in this registry.
     */
    CanvassingWalletRegistry public registry;

    /**
     * @notice Returns true if an eoAddress has already claimed a task reward for a given taskId (EOA path).
     * @dev Key: keccak256(abi.encodePacked(taskId, eoAddress))
     */
    mapping(bytes32 => bool) public isTaskRewarded;

    /**
     * @notice True once task reward has been paid for this task to this smart account (any path).
     * @dev Key: keccak256(abi.encodePacked(taskId, smartAccountContractAddress))
     */
    mapping(bytes32 => bool) public isTaskRewardPaidToSmartAccount;

    /**
     * @notice Returns true if an eoAddress has already claimed an achievement reward for a given achievementId.
     * @dev Key: keccak256(abi.encodePacked(achievementId, eoAddress))
     */
    mapping(bytes32 => bool) public isAchievementRewarded;

    /**
     * @notice Returns true if an eoAddress has already claimed a referral reward for a given referralId.
     * @dev Key: keccak256(abi.encodePacked(referralId, eoAddress))
     */
    mapping(bytes32 => bool) public isReferralRewarded;

    /**
     * @notice Returns true if a reward claim signature has already been used.
     * @dev Covers both task and achievement signatures — signatures are globally unique.
     */
    mapping(bytes => bool) public isSignatureUsed;

    /**
     * @notice Total number of task rewards distributed.
     */
    uint256 public totalTaskRewards;

    /**
     * @notice Total number of achievement rewards distributed.
     */
    uint256 public totalAchievementRewards;

    /**
     * @notice Total number of referral rewards distributed.
     */
    uint256 public totalReferralRewards;

    /**
     * @notice Total amount donated from reward claims, in token wei.
     * @dev Aggregates all tokens forwarded to donationContractAddress across claim types.
     */
    uint256 public totalDonationsFromRewards;

    /**
     * @notice Configured GoodDollar token address.
     * @dev When donation rewards use this token, ERC677 transferAndCall is used.
     */
    address public goodDollarToken;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted when a task reward is successfully distributed.
     * @param eoAddress                   The EO wallet address of the participant.
     * @param smartAccountContractAddress The smart account that received the tokens.
     * @param taskId                      The task identifier.
     * @param token                       The ERC20 token address used for the reward.
     * @param amount                      The amount of tokens transferred, in wei.
     */
    event TaskRewarded(
        address indexed eoAddress,
        address indexed smartAccountContractAddress,
        address indexed recipientAddress,
        string taskId,
        address token,
        uint256 amount
    );

    /**
     * @notice Emitted when an achievement reward is successfully distributed.
     * @param eoAddress                   The EO wallet address of the participant.
     * @param smartAccountContractAddress The smart account that received the tokens.
     * @param achievementId               The achievement identifier.
     * @param token                       The ERC20 token address used for the reward.
     * @param amount                      The amount of tokens transferred, in wei.
     */
    event AchievementRewarded(
        address indexed eoAddress,
        address indexed smartAccountContractAddress,
        address indexed recipientAddress,
        string achievementId,
        address token,
        uint256 amount
    );

    /**
     * @notice Emitted when a referral reward is successfully distributed.
     * @param eoAddress                   The EO wallet address of the participant.
     * @param smartAccountContractAddress The smart account that called this function.
     * @param recipientAddress            The ERC20 token transfer destination.
     * @param referralId                  The referral identifier.
     * @param token                       The ERC20 token address used for the reward.
     * @param amount                      The amount of tokens transferred, in wei.
     */
    event ReferralRewarded(
        address indexed eoAddress,
        address indexed referredEoAddress,
        address indexed smartAccountContractAddress,
        address recipientAddress,
        string referralId,
        address token,
        uint256 amount
    );

    /**
     * @notice Emitted when a task reward is split between a recipient and a donation contract.
     */
    event TaskRewardedWithDonation(
        address indexed eoAddress,
        address indexed smartAccountContractAddress,
        address indexed recipientAddress,
        address donationContractAddress,
        string taskId,
        address token,
        uint256 amount,
        uint256 recipientAmount,
        uint256 donationAmount,
        uint256 donationBasisPoints
    );

    /**
     * @notice Emitted when an achievement reward is split between a recipient and a donation contract.
     */
    event AchievementRewardedWithDonation(
        address indexed eoAddress,
        address indexed smartAccountContractAddress,
        address indexed recipientAddress,
        address donationContractAddress,
        string achievementId,
        address token,
        uint256 amount,
        uint256 recipientAmount,
        uint256 donationAmount,
        uint256 donationBasisPoints
    );

    /**
     * @notice Emitted when a referral reward is split between a recipient and a donation contract.
     */
    event ReferralRewardedWithDonation(
        address indexed eoAddress,
        address indexed referredEoAddress,
        address indexed smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string referralId,
        address token,
        uint256 amount,
        uint256 recipientAmount,
        uint256 donationAmount,
        uint256 donationBasisPoints
    );

    /**
     * @notice Emitted when the task manager reference is updated.
     * @param oldTaskManager The previous task manager address.
     * @param newTaskManager The new task manager address.
     */
    event TaskManagerUpdated(
        address indexed oldTaskManager,
        address indexed newTaskManager
    );

    /**
     * @notice Emitted when the wallet registry reference is updated.
     * @param oldRegistry The previous registry address.
     * @param newRegistry The new registry address.
     */
    event RegistryUpdated(
        address indexed oldRegistry,
        address indexed newRegistry
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

    /**
     * @notice Emitted when the owner withdraws tokens from the contract.
     * @param token  The ERC20 token address withdrawn.
     * @param to     The recipient address.
     * @param amount The amount withdrawn, in wei.
     */
    event TokenWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    /**
     * @notice Emitted when the GoodDollar token address is updated.
     * @param oldGoodDollarToken The previous GoodDollar token address.
     * @param newGoodDollarToken The new GoodDollar token address.
     */
    event GoodDollarTokenUpdated(
        address indexed oldGoodDollarToken,
        address indexed newGoodDollarToken
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
     * @param _owner       The address that will own and administer this contract.
     * @param _signer      The backend signer address that authorises reward claims.
     * @param _taskManager The address of the deployed CanvassingTaskManager.
     */
    function initialize(
        address _owner,
        address _signer,
        address _taskManager
    ) public initializer {
        require(_owner != address(0), "CanvassingRewarder: owner cannot be zero address");
        require(_signer != address(0), "CanvassingRewarder: signer cannot be zero address");
        require(_taskManager != address(0), "CanvassingRewarder: taskManager cannot be zero address");

        __Ownable_init(_owner);
        __Pausable_init();
        __EIP712_init("CanvassingRewarder", "1");

        signer = _signer;
        taskManager = CanvassingTaskManager(_taskManager);
        version = 1;
    }

    // -------------------------------------------------------------------------
    // Core logic — Task rewards
    // -------------------------------------------------------------------------

    /**
     * @notice Claim a task completion reward (sponsored userOp).
     * @dev msg.sender must be smartAccountContractAddress (same as screening caller).
     *      EIP-712 still binds eoAddress + smartAccount for replay and identity.
     *
     * @param eoAddress                   Participant EOA (signed by backend; not required to be msg.sender).
     * @param smartAccountContractAddress Must equal msg.sender (screening AA).
     * @param recipientAddress            EIP-712; ERC20 transfer destination.
     * @param taskId                      The unique identifier of the completed task.
     * @param token                       The ERC20 token to pay the reward in.
     * @param amount                      The reward amount in wei, as specified by the backend.
     * @param nonce                       A unique number to prevent signature replay.
     * @param signature                   EIP-712 signature from the backend signer.
     */
    function claimTaskReward(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        string calldata taskId,
        address token,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external whenNotPaused {
        require(
            msg.sender == smartAccountContractAddress,
            "CanvassingRewarder: sender must be smartAccountContractAddress"
        );
        require(eoAddress != address(0), "CanvassingRewarder: eoAddress cannot be zero address");
        require(smartAccountContractAddress != address(0), "CanvassingRewarder: smartAccount cannot be zero address");
        require(recipientAddress != address(0), "CanvassingRewarder: recipient cannot be zero address");
        require(bytes(taskId).length > 0, "CanvassingRewarder: taskId cannot be empty");
        require(token != address(0), "CanvassingRewarder: token cannot be zero address");
        require(amount > 0, "CanvassingRewarder: amount must be greater than zero");

        // Screening is recorded per smart account (see CanvassingTaskManager)
        require(
            taskManager.checkIfScreened(taskId, smartAccountContractAddress),
            "CanvassingRewarder: participant not screened for this task"
        );

        bytes32 slot = _taskSlot(taskId, eoAddress);
        bytes32 payoutSlot = _taskPayoutSlot(taskId, smartAccountContractAddress);
        require(!isTaskRewarded[slot], "CanvassingRewarder: task reward already claimed");
        require(
            !isTaskRewardPaidToSmartAccount[payoutSlot],
            "CanvassingRewarder: task reward already paid for this smart account"
        );
        require(!isSignatureUsed[signature], "CanvassingRewarder: signature already used");

        require(
            _verifyTaskRewardSignature(
                eoAddress,
                smartAccountContractAddress,
                recipientAddress,
                taskId,
                token,
                amount,
                nonce,
                signature
            ),
            "CanvassingRewarder: invalid signature"
        );

        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "CanvassingRewarder: insufficient token balance"
        );

        isTaskRewarded[slot] = true;
        isTaskRewardPaidToSmartAccount[payoutSlot] = true;
        isSignatureUsed[signature] = true;

        unchecked { ++totalTaskRewards; }

        bool success = IERC20(token).transfer(recipientAddress, amount);
        require(success, "CanvassingRewarder: token transfer failed");

        emit TaskRewarded(eoAddress, smartAccountContractAddress, recipientAddress, taskId, token, amount);
    }

    /**
     * @notice Claim a task completion reward with an on-chain donation split.
     * @dev `donationBasisPoints` is expressed over 10_000 (1000 = 10%, 10000 = 100%).
     */
    function claimTaskRewardWithDonation(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string calldata taskId,
        address token,
        uint256 amount,
        uint256 donationBasisPoints,
        uint256 nonce,
        bytes calldata signature
    ) external whenNotPaused {
        require(
            msg.sender == smartAccountContractAddress,
            "CanvassingRewarder: sender must be smartAccountContractAddress"
        );
        require(eoAddress != address(0), "CanvassingRewarder: eoAddress cannot be zero address");
        require(smartAccountContractAddress != address(0), "CanvassingRewarder: smartAccount cannot be zero address");
        require(donationContractAddress != address(0), "CanvassingRewarder: donation contract cannot be zero address");
        require(bytes(taskId).length > 0, "CanvassingRewarder: taskId cannot be empty");
        require(token != address(0), "CanvassingRewarder: token cannot be zero address");
        require(amount > 0, "CanvassingRewarder: amount must be greater than zero");
        require(
            donationBasisPoints > 0 && donationBasisPoints <= 10000,
            "CanvassingRewarder: invalid donation basis points"
        );

        // Screening is recorded per smart account (see CanvassingTaskManager)
        require(
            taskManager.checkIfScreened(taskId, smartAccountContractAddress),
            "CanvassingRewarder: participant not screened for this task"
        );

        bytes32 slot = _taskSlot(taskId, eoAddress);
        bytes32 payoutSlot = _taskPayoutSlot(taskId, smartAccountContractAddress);
        require(!isTaskRewarded[slot], "CanvassingRewarder: task reward already claimed");
        require(
            !isTaskRewardPaidToSmartAccount[payoutSlot],
            "CanvassingRewarder: task reward already paid for this smart account"
        );
        require(!isSignatureUsed[signature], "CanvassingRewarder: signature already used");

        require(
            _verifyTaskRewardWithDonationSignature(
                eoAddress,
                smartAccountContractAddress,
                recipientAddress,
                donationContractAddress,
                taskId,
                token,
                amount,
                donationBasisPoints,
                nonce,
                signature
            ),
            "CanvassingRewarder: invalid signature"
        );

        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "CanvassingRewarder: insufficient token balance"
        );

        isTaskRewarded[slot] = true;
        isTaskRewardPaidToSmartAccount[payoutSlot] = true;
        isSignatureUsed[signature] = true;

        unchecked { ++totalTaskRewards; }

        _settleTaskRewardWithDonation(
            eoAddress,
            smartAccountContractAddress,
            recipientAddress,
            donationContractAddress,
            taskId,
            token,
            amount,
            donationBasisPoints
        );
    }

    // -------------------------------------------------------------------------
    // Core logic — Achievement rewards
    // -------------------------------------------------------------------------

    /**
     * @notice Claim an in-app achievement reward.
     * @dev Sponsored userOp: msg.sender must be smartAccountContractAddress (same as task claims).
     *      Validates the backend signature before transferring tokens to the smart account.
     *
     * @param eoAddress                   The EO wallet address of the participant (EIP-712 identity).
     * @param smartAccountContractAddress The smart account that calls this function.
     * @param recipientAddress            EIP-712; ERC20 transfer destination.
     * @param achievementId               The unique identifier of the achievement.
     * @param token                       The ERC20 token to pay the reward in.
     * @param amount                      The reward amount in wei, as specified by the backend.
     * @param nonce                       A unique number to prevent signature replay.
     * @param signature                   EIP-712 signature from the backend signer.
     */
    function claimAchievementReward(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        string calldata achievementId,
        address token,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external whenNotPaused {
        require(
            msg.sender == smartAccountContractAddress,
            "CanvassingRewarder: sender must be smartAccountContractAddress"
        );
        require(eoAddress != address(0), "CanvassingRewarder: eoAddress cannot be zero address");
        require(smartAccountContractAddress != address(0), "CanvassingRewarder: smartAccount cannot be zero address");
        require(recipientAddress != address(0), "CanvassingRewarder: recipient cannot be zero address");
        require(bytes(achievementId).length > 0, "CanvassingRewarder: achievementId cannot be empty");
        require(token != address(0), "CanvassingRewarder: token cannot be zero address");
        require(amount > 0, "CanvassingRewarder: amount must be greater than zero");

        bytes32 slot = _achievementSlot(achievementId, eoAddress);
        require(!isAchievementRewarded[slot], "CanvassingRewarder: achievement reward already claimed");
        require(!isSignatureUsed[signature], "CanvassingRewarder: signature already used");

        require(
            _verifyAchievementRewardSignature(
                eoAddress,
                smartAccountContractAddress,
                recipientAddress,
                achievementId,
                token,
                amount,
                nonce,
                signature
            ),
            "CanvassingRewarder: invalid signature"
        );

        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "CanvassingRewarder: insufficient token balance"
        );

        isAchievementRewarded[slot] = true;
        isSignatureUsed[signature] = true;

        unchecked { ++totalAchievementRewards; }

        bool success = IERC20(token).transfer(recipientAddress, amount);
        require(success, "CanvassingRewarder: token transfer failed");

        emit AchievementRewarded(
            eoAddress,
            smartAccountContractAddress,
            recipientAddress,
            achievementId,
            token,
            amount
        );
    }

    /**
     * @notice Claim an achievement reward with an on-chain donation split.
     * @dev `donationBasisPoints` is expressed over 10_000 (1000 = 10%, 10000 = 100%).
     */
    function claimAchievementRewardWithDonation(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string calldata achievementId,
        address token,
        uint256 amount,
        uint256 donationBasisPoints,
        uint256 nonce,
        bytes calldata signature
    ) external whenNotPaused {
        require(
            msg.sender == smartAccountContractAddress,
            "CanvassingRewarder: sender must be smartAccountContractAddress"
        );
        require(eoAddress != address(0), "CanvassingRewarder: eoAddress cannot be zero address");
        require(smartAccountContractAddress != address(0), "CanvassingRewarder: smartAccount cannot be zero address");
        require(donationContractAddress != address(0), "CanvassingRewarder: donation contract cannot be zero address");
        require(bytes(achievementId).length > 0, "CanvassingRewarder: achievementId cannot be empty");
        require(token != address(0), "CanvassingRewarder: token cannot be zero address");
        require(amount > 0, "CanvassingRewarder: amount must be greater than zero");
        require(
            donationBasisPoints > 0 && donationBasisPoints <= 10000,
            "CanvassingRewarder: invalid donation basis points"
        );

        bytes32 slot = _achievementSlot(achievementId, eoAddress);
        require(!isAchievementRewarded[slot], "CanvassingRewarder: achievement reward already claimed");
        require(!isSignatureUsed[signature], "CanvassingRewarder: signature already used");

        require(
            _verifyAchievementRewardWithDonationSignature(
                eoAddress,
                smartAccountContractAddress,
                recipientAddress,
                donationContractAddress,
                achievementId,
                token,
                amount,
                donationBasisPoints,
                nonce,
                signature
            ),
            "CanvassingRewarder: invalid signature"
        );

        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "CanvassingRewarder: insufficient token balance"
        );

        isAchievementRewarded[slot] = true;
        isSignatureUsed[signature] = true;

        unchecked { ++totalAchievementRewards; }

        _settleAchievementRewardWithDonation(
            eoAddress,
            smartAccountContractAddress,
            recipientAddress,
            donationContractAddress,
            achievementId,
            token,
            amount,
            donationBasisPoints
        );
    }

    // -------------------------------------------------------------------------
    // Core logic — Referral rewards
    // -------------------------------------------------------------------------

    /**
     * @notice Claim a referral reward.
     * @dev Sponsored userOp: msg.sender must be smartAccountContractAddress.
     *
     * @param eoAddress                   The EO wallet address of the participant (EIP-712 identity).
     * @param smartAccountContractAddress The smart account that calls this function.
     * @param recipientAddress            EIP-712; ERC20 transfer destination.
     * @param referralId                  The unique identifier of the referral.
     * @param token                       The ERC20 token to pay the reward in.
     * @param amount                      The reward amount in wei, as specified by the backend.
     * @param nonce                       A unique number to prevent signature replay.
     * @param signature                   EIP-712 signature from the backend signer.
     */
    function claimReferralReward(
        address eoAddress,
        address referredEoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        string calldata referralId,
        address token,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external whenNotPaused {
        require(
            msg.sender == smartAccountContractAddress,
            "CanvassingRewarder: sender must be smartAccountContractAddress"
        );
        require(eoAddress != address(0), "CanvassingRewarder: eoAddress cannot be zero address");
        require(referredEoAddress != address(0), "CanvassingRewarder: referredEoAddress cannot be zero address");
        require(smartAccountContractAddress != address(0), "CanvassingRewarder: smartAccount cannot be zero address");
        require(recipientAddress != address(0), "CanvassingRewarder: recipient cannot be zero address");
        require(bytes(referralId).length > 0, "CanvassingRewarder: referralId cannot be empty");
        require(token != address(0), "CanvassingRewarder: token cannot be zero address");
        require(amount > 0, "CanvassingRewarder: amount must be greater than zero");

        require(address(registry) != address(0), "CanvassingRewarder: registry not configured");
        require(
            registry.isWalletLogged(referredEoAddress),
            "CanvassingRewarder: referredEoAddress not registered"
        );

        require(
            !isReferralRewarded[_referralSlot(referralId, eoAddress, referredEoAddress)],
            "CanvassingRewarder: referral reward already claimed"
        );
        require(!isSignatureUsed[signature], "CanvassingRewarder: signature already used");

        require(
            _verifyReferralRewardSignature(
                eoAddress,
                referredEoAddress,
                smartAccountContractAddress,
                recipientAddress,
                referralId,
                token,
                amount,
                nonce,
                signature
            ),
            "CanvassingRewarder: invalid signature"
        );

        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "CanvassingRewarder: insufficient token balance"
        );

        isReferralRewarded[_referralSlot(referralId, eoAddress, referredEoAddress)] = true;
        isSignatureUsed[signature] = true;

        unchecked { ++totalReferralRewards; }

        bool success = IERC20(token).transfer(recipientAddress, amount);
        require(success, "CanvassingRewarder: token transfer failed");

        emit ReferralRewarded(
            eoAddress,
            referredEoAddress,
            smartAccountContractAddress,
            recipientAddress,
            referralId,
            token,
            amount
        );
    }

    /**
     * @notice Claim a referral reward with an on-chain donation split.
     * @dev `donationBasisPoints` is expressed over 10_000 (1000 = 10%, 10000 = 100%).
     */
    function claimReferralRewardWithDonation(
        address eoAddress,
        address referredEoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string calldata referralId,
        address token,
        uint256 amount,
        uint256 donationBasisPoints,
        uint256 nonce,
        bytes calldata signature
    ) external whenNotPaused {
        require(
            msg.sender == smartAccountContractAddress,
            "CanvassingRewarder: sender must be smartAccountContractAddress"
        );
        require(eoAddress != address(0), "CanvassingRewarder: eoAddress cannot be zero address");
        require(referredEoAddress != address(0), "CanvassingRewarder: referredEoAddress cannot be zero address");
        require(smartAccountContractAddress != address(0), "CanvassingRewarder: smartAccount cannot be zero address");
        require(donationContractAddress != address(0), "CanvassingRewarder: donation contract cannot be zero address");
        require(bytes(referralId).length > 0, "CanvassingRewarder: referralId cannot be empty");
        require(token != address(0), "CanvassingRewarder: token cannot be zero address");
        require(amount > 0, "CanvassingRewarder: amount must be greater than zero");
        require(
            donationBasisPoints > 0 && donationBasisPoints <= 10000,
            "CanvassingRewarder: invalid donation basis points"
        );

        require(address(registry) != address(0), "CanvassingRewarder: registry not configured");
        require(
            registry.isWalletLogged(referredEoAddress),
            "CanvassingRewarder: referredEoAddress not registered"
        );

        require(
            !isReferralRewarded[_referralSlot(referralId, eoAddress, referredEoAddress)],
            "CanvassingRewarder: referral reward already claimed"
        );
        require(!isSignatureUsed[signature], "CanvassingRewarder: signature already used");

        require(
            _verifyReferralRewardWithDonationSignature(
                eoAddress,
                referredEoAddress,
                smartAccountContractAddress,
                recipientAddress,
                donationContractAddress,
                referralId,
                token,
                amount,
                donationBasisPoints,
                nonce,
                signature
            ),
            "CanvassingRewarder: invalid signature"
        );

        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "CanvassingRewarder: insufficient token balance"
        );

        isReferralRewarded[_referralSlot(referralId, eoAddress, referredEoAddress)] = true;
        isSignatureUsed[signature] = true;

        unchecked { ++totalReferralRewards; }

        _settleReferralRewardWithDonation(
            eoAddress,
            referredEoAddress,
            smartAccountContractAddress,
            recipientAddress,
            donationContractAddress,
            referralId,
            token,
            amount,
            donationBasisPoints
        );
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Check whether an eoAddress has claimed a task reward for a given taskId.
     * @param taskId    The task identifier.
     * @param eoAddress The EO wallet address to check.
     * @return True if already claimed.
     */
    function checkIfTaskRewarded(
        string calldata taskId,
        address eoAddress
    ) external view returns (bool) {
        return isTaskRewarded[_taskSlot(taskId, eoAddress)];
    }

    /**
     * @notice Check whether an eoAddress has claimed an achievement reward for a given achievementId.
     * @param achievementId The achievement identifier.
     * @param eoAddress     The EO wallet address to check.
     * @return True if already claimed.
     */
    function checkIfAchievementRewarded(
        string calldata achievementId,
        address eoAddress
    ) external view returns (bool) {
        return isAchievementRewarded[_achievementSlot(achievementId, eoAddress)];
    }

    /**
     * @notice Check whether an eoAddress has claimed a referral reward for a given referralId.
     * @param referralId The referral identifier.
     * @param eoAddress  The EO wallet address to check.
     * @return True if already claimed.
     */
    function checkIfReferralRewarded(
        string calldata referralId,
        address eoAddress,
        address referredEoAddress
    ) external view returns (bool) {
        return isReferralRewarded[_referralSlot(referralId, eoAddress, referredEoAddress)];
    }

    /**
     * @notice Get the current balance of a given ERC20 token held by this contract.
     * @param token The ERC20 token address.
     * @return The balance in wei.
     */
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /**
     * @notice Update the backend signer address.
     * @param newSigner The new signer address.
     */
    function setSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "CanvassingRewarder: signer cannot be zero address");
        address oldSigner = signer;
        signer = newSigner;
        emit SignerUpdated(oldSigner, newSigner);
    }

    /**
     * @notice Update the CanvassingTaskManager reference.
     * @param newTaskManager The new task manager address.
     */
    function setTaskManager(address newTaskManager) external onlyOwner {
        require(newTaskManager != address(0), "CanvassingRewarder: taskManager cannot be zero address");
        address oldTaskManager = address(taskManager);
        taskManager = CanvassingTaskManager(newTaskManager);
        emit TaskManagerUpdated(oldTaskManager, newTaskManager);
    }

    /**
     * @notice Update the CanvassingWalletRegistry reference.
     * @param newRegistry The new registry address.
     */
    function setRegistry(address newRegistry) external onlyOwner {
        require(newRegistry != address(0), "CanvassingRewarder: registry cannot be zero address");
        address oldRegistry = address(registry);
        registry = CanvassingWalletRegistry(newRegistry);
        emit RegistryUpdated(oldRegistry, newRegistry);
    }

    /**
     * @notice Update the GoodDollar token address used for ERC677 donation transfers.
     * @param newGoodDollarToken The new GoodDollar token address.
     */
    function setGoodDollarToken(address newGoodDollarToken) external onlyOwner {
        require(
            newGoodDollarToken != address(0),
            "CanvassingRewarder: goodDollarToken cannot be zero address"
        );

        address oldGoodDollarToken = goodDollarToken;
        goodDollarToken = newGoodDollarToken;

        emit GoodDollarTokenUpdated(oldGoodDollarToken, newGoodDollarToken);
    }

    /**
     * @notice Withdraw any ERC20 token balance from the contract to a specified address.
     * @dev Used by the owner to recover funds or rebalance across deployments.
     * @param token  The ERC20 token to withdraw.
     * @param to     The recipient address.
     * @param amount The amount to withdraw, in wei.
     */
    function withdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "CanvassingRewarder: token cannot be zero address");
        require(to != address(0), "CanvassingRewarder: recipient cannot be zero address");
        require(amount > 0, "CanvassingRewarder: amount must be greater than zero");
        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "CanvassingRewarder: insufficient balance"
        );

        bool success = IERC20(token).transfer(to, amount);
        require(success, "CanvassingRewarder: withdrawal failed");

        emit TokenWithdrawn(token, to, amount);
    }

    /**
     * @notice Pause all reward claim operations.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resume all reward claim operations.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Derives the storage slot key for a (taskId, eoAddress) pair.
     */
    function _taskSlot(
        string calldata taskId,
        address eoAddress
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(taskId, eoAddress));
    }

    function _taskPayoutSlot(
        string calldata taskId,
        address smartAccountContractAddress
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(taskId, smartAccountContractAddress));
    }

    /**
     * @dev Derives the storage slot key for an (achievementId, eoAddress) pair.
     */
    function _achievementSlot(
        string calldata achievementId,
        address eoAddress
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(achievementId, eoAddress));
    }

    /**
     * @dev Derives the storage slot key for a (referralId, eoAddress) pair.
     */
    function _referralSlot(
        string calldata referralId,
        address eoAddress,
        address referredEoAddress
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(referralId, eoAddress, referredEoAddress));
    }

    /**
     * @dev Verifies an EIP-712 task reward signature against the stored signer.
     */
    function _verifyTaskRewardSignature(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        string calldata taskId,
        address token,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    TASK_REWARD_TYPEHASH,
                    eoAddress,
                    smartAccountContractAddress,
                    recipientAddress,
                    keccak256(bytes(taskId)),
                    token,
                    amount,
                    nonce
                )
            )
        );
        return ECDSA.recover(digest, signature) == signer;
    }

    /**
     * @dev Verifies an EIP-712 task reward with donation signature against the stored signer.
     */
    function _verifyTaskRewardWithDonationSignature(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string calldata taskId,
        address token,
        uint256 amount,
        uint256 donationBasisPoints,
        uint256 nonce,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    TASK_REWARD_WITH_DONATION_TYPEHASH,
                    eoAddress,
                    smartAccountContractAddress,
                    recipientAddress,
                    donationContractAddress,
                    keccak256(bytes(taskId)),
                    token,
                    amount,
                    donationBasisPoints,
                    nonce
                )
            )
        );
        return ECDSA.recover(digest, signature) == signer;
    }

    /**
     * @dev Verifies an EIP-712 achievement reward signature against the stored signer.
     */
    function _verifyAchievementRewardSignature(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        string calldata achievementId,
        address token,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ACHIEVEMENT_REWARD_TYPEHASH,
                    eoAddress,
                    smartAccountContractAddress,
                    recipientAddress,
                    keccak256(bytes(achievementId)),
                    token,
                    amount,
                    nonce
                )
            )
        );
        return ECDSA.recover(digest, signature) == signer;
    }

    /**
     * @dev Verifies an EIP-712 achievement reward with donation signature against the stored signer.
     */
    function _verifyAchievementRewardWithDonationSignature(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string calldata achievementId,
        address token,
        uint256 amount,
        uint256 donationBasisPoints,
        uint256 nonce,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ACHIEVEMENT_REWARD_WITH_DONATION_TYPEHASH,
                    eoAddress,
                    smartAccountContractAddress,
                    recipientAddress,
                    donationContractAddress,
                    keccak256(bytes(achievementId)),
                    token,
                    amount,
                    donationBasisPoints,
                    nonce
                )
            )
        );
        return ECDSA.recover(digest, signature) == signer;
    }

    /**
     * @dev Verifies an EIP-712 referral reward signature against the stored signer.
     */
    function _verifyReferralRewardSignature(
        address eoAddress,
        address referredEoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        string calldata referralId,
        address token,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    REFERRAL_REWARD_TYPEHASH,
                    eoAddress,
                    referredEoAddress,
                    smartAccountContractAddress,
                    recipientAddress,
                    keccak256(bytes(referralId)),
                    token,
                    amount,
                    nonce
                )
            )
        );
        return ECDSA.recover(digest, signature) == signer;
    }

    /**
     * @dev Verifies an EIP-712 referral reward with donation signature against the stored signer.
     */
    function _verifyReferralRewardWithDonationSignature(
        address eoAddress,
        address referredEoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string calldata referralId,
        address token,
        uint256 amount,
        uint256 donationBasisPoints,
        uint256 nonce,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    REFERRAL_REWARD_WITH_DONATION_TYPEHASH,
                    eoAddress,
                    referredEoAddress,
                    smartAccountContractAddress,
                    recipientAddress,
                    donationContractAddress,
                    keccak256(bytes(referralId)),
                    token,
                    amount,
                    donationBasisPoints,
                    nonce
                )
            )
        );
        return ECDSA.recover(digest, signature) == signer;
    }

    /**
     * @dev Splits reward amount and transfers recipient + donation portions.
     */
    function _splitAndTransferReward(
        address token,
        address recipientAddress,
        address donationContractAddress,
        uint256 amount,
        uint256 donationBasisPoints
    ) internal returns (uint256 recipientAmount, uint256 donationAmount) {
        donationAmount = (amount * donationBasisPoints) / 10000;
        recipientAmount = amount - donationAmount;

        if (recipientAmount > 0) {
            require(recipientAddress != address(0), "CanvassingRewarder: recipient cannot be zero address");
            bool recipientTransferSuccess = IERC20(token).transfer(recipientAddress, recipientAmount);
            require(recipientTransferSuccess, "CanvassingRewarder: recipient transfer failed");
        }

        require(donationAmount > 0, "CanvassingRewarder: donation amount must be greater than zero");
        bool donationTransferSuccess;
        if (token == goodDollarToken) {
            donationTransferSuccess = IERC677(token).transferAndCall(
                donationContractAddress,
                donationAmount,
                hex""
            );
        } else {
            donationTransferSuccess = IERC20(token).transfer(donationContractAddress, donationAmount);
        }
        require(donationTransferSuccess, "CanvassingRewarder: donation transfer failed");

        unchecked {
            totalDonationsFromRewards += donationAmount;
        }
    }

    function _settleTaskRewardWithDonation(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string calldata taskId,
        address token,
        uint256 amount,
        uint256 donationBasisPoints
    ) internal {
        (uint256 recipientAmount, uint256 donationAmount) = _splitAndTransferReward(
            token,
            recipientAddress,
            donationContractAddress,
            amount,
            donationBasisPoints
        );

        emit TaskRewardedWithDonation(
            eoAddress,
            smartAccountContractAddress,
            recipientAddress,
            donationContractAddress,
            taskId,
            token,
            amount,
            recipientAmount,
            donationAmount,
            donationBasisPoints
        );
    }

    function _settleAchievementRewardWithDonation(
        address eoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string calldata achievementId,
        address token,
        uint256 amount,
        uint256 donationBasisPoints
    ) internal {
        (uint256 recipientAmount, uint256 donationAmount) = _splitAndTransferReward(
            token,
            recipientAddress,
            donationContractAddress,
            amount,
            donationBasisPoints
        );

        emit AchievementRewardedWithDonation(
            eoAddress,
            smartAccountContractAddress,
            recipientAddress,
            donationContractAddress,
            achievementId,
            token,
            amount,
            recipientAmount,
            donationAmount,
            donationBasisPoints
        );
    }

    function _settleReferralRewardWithDonation(
        address eoAddress,
        address referredEoAddress,
        address smartAccountContractAddress,
        address recipientAddress,
        address donationContractAddress,
        string calldata referralId,
        address token,
        uint256 amount,
        uint256 donationBasisPoints
    ) internal {
        (uint256 recipientAmount, uint256 donationAmount) = _splitAndTransferReward(
            token,
            recipientAddress,
            donationContractAddress,
            amount,
            donationBasisPoints
        );

        emit ReferralRewardedWithDonation(
            eoAddress,
            referredEoAddress,
            smartAccountContractAddress,
            recipientAddress,
            donationContractAddress,
            referralId,
            token,
            amount,
            recipientAmount,
            donationAmount,
            donationBasisPoints
        );
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
            "CanvassingRewarder: newVersion must be greater than current version"
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

    uint256[45] private __gap;
}

