export const canvassingRewarderABI = [
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"internalType": "string",
				"name": "achievementId",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "nonce",
				"type": "uint256"
			},
			{
				"internalType": "bytes",
				"name": "signature",
				"type": "bytes"
			}
		],
		"name": "claimAchievementReward",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "donationContractAddress",
				"type": "address"
			},
			{
				"internalType": "string",
				"name": "achievementId",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "donationBasisPoints",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "nonce",
				"type": "uint256"
			},
			{
				"internalType": "bytes",
				"name": "signature",
				"type": "bytes"
			}
		],
		"name": "claimAchievementRewardWithDonation",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [],
		"stateMutability": "nonpayable",
		"type": "constructor"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "target",
				"type": "address"
			}
		],
		"name": "AddressEmptyCode",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "ECDSAInvalidSignature",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "uint256",
				"name": "length",
				"type": "uint256"
			}
		],
		"name": "ECDSAInvalidSignatureLength",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "s",
				"type": "bytes32"
			}
		],
		"name": "ECDSAInvalidSignatureS",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "implementation",
				"type": "address"
			}
		],
		"name": "ERC1967InvalidImplementation",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "ERC1967NonPayable",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "EnforcedPause",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "ExpectedPause",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "FailedCall",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "InvalidInitialization",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "NotInitializing",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "owner",
				"type": "address"
			}
		],
		"name": "OwnableInvalidOwner",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "account",
				"type": "address"
			}
		],
		"name": "OwnableUnauthorizedAccount",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "UUPSUnauthorizedCallContext",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "slot",
				"type": "bytes32"
			}
		],
		"name": "UUPSUnsupportedProxiableUUID",
		"type": "error"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "string",
				"name": "achievementId",
				"type": "string"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			}
		],
		"name": "AchievementRewarded",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "donationContractAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "string",
				"name": "achievementId",
				"type": "string"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "recipientAmount",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "donationAmount",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "donationBasisPoints",
				"type": "uint256"
			}
		],
		"name": "AchievementRewardedWithDonation",
		"type": "event"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "referredEoAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"internalType": "string",
				"name": "referralId",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "nonce",
				"type": "uint256"
			},
			{
				"internalType": "bytes",
				"name": "signature",
				"type": "bytes"
			}
		],
		"name": "claimReferralReward",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "referredEoAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "donationContractAddress",
				"type": "address"
			},
			{
				"internalType": "string",
				"name": "referralId",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "donationBasisPoints",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "nonce",
				"type": "uint256"
			},
			{
				"internalType": "bytes",
				"name": "signature",
				"type": "bytes"
			}
		],
		"name": "claimReferralRewardWithDonation",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"internalType": "string",
				"name": "taskId",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "nonce",
				"type": "uint256"
			},
			{
				"internalType": "bytes",
				"name": "signature",
				"type": "bytes"
			}
		],
		"name": "claimTaskReward",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "donationContractAddress",
				"type": "address"
			},
			{
				"internalType": "string",
				"name": "taskId",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "donationBasisPoints",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "nonce",
				"type": "uint256"
			},
			{
				"internalType": "bytes",
				"name": "signature",
				"type": "bytes"
			}
		],
		"name": "claimTaskRewardWithDonation",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "oldVersion",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "newVersion",
				"type": "uint256"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "newImplementation",
				"type": "address"
			}
		],
		"name": "ContractUpgraded",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [],
		"name": "EIP712DomainChanged",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "oldGoodDollarToken",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "newGoodDollarToken",
				"type": "address"
			}
		],
		"name": "GoodDollarTokenUpdated",
		"type": "event"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "_owner",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "_signer",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "_taskManager",
				"type": "address"
			}
		],
		"name": "initialize",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "uint64",
				"name": "version",
				"type": "uint64"
			}
		],
		"name": "Initialized",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "previousOwner",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "newOwner",
				"type": "address"
			}
		],
		"name": "OwnershipTransferred",
		"type": "event"
	},
	{
		"inputs": [],
		"name": "pause",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "address",
				"name": "account",
				"type": "address"
			}
		],
		"name": "Paused",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "referredEoAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "string",
				"name": "referralId",
				"type": "string"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			}
		],
		"name": "ReferralRewarded",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "referredEoAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "donationContractAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "string",
				"name": "referralId",
				"type": "string"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "recipientAmount",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "donationAmount",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "donationBasisPoints",
				"type": "uint256"
			}
		],
		"name": "ReferralRewardedWithDonation",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "oldRegistry",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "newRegistry",
				"type": "address"
			}
		],
		"name": "RegistryUpdated",
		"type": "event"
	},
	{
		"inputs": [],
		"name": "renounceOwnership",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newGoodDollarToken",
				"type": "address"
			}
		],
		"name": "setGoodDollarToken",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newRegistry",
				"type": "address"
			}
		],
		"name": "setRegistry",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newSigner",
				"type": "address"
			}
		],
		"name": "setSigner",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newTaskManager",
				"type": "address"
			}
		],
		"name": "setTaskManager",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "oldSigner",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "newSigner",
				"type": "address"
			}
		],
		"name": "SignerUpdated",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "oldTaskManager",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "newTaskManager",
				"type": "address"
			}
		],
		"name": "TaskManagerUpdated",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "string",
				"name": "taskId",
				"type": "string"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			}
		],
		"name": "TaskRewarded",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "smartAccountContractAddress",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "recipientAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "donationContractAddress",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "string",
				"name": "taskId",
				"type": "string"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "recipientAmount",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "donationAmount",
				"type": "uint256"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "donationBasisPoints",
				"type": "uint256"
			}
		],
		"name": "TaskRewardedWithDonation",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "to",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			}
		],
		"name": "TokenWithdrawn",
		"type": "event"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newOwner",
				"type": "address"
			}
		],
		"name": "transferOwnership",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "unpause",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "address",
				"name": "account",
				"type": "address"
			}
		],
		"name": "Unpaused",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "implementation",
				"type": "address"
			}
		],
		"name": "Upgraded",
		"type": "event"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newImplementation",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "newVersion",
				"type": "uint256"
			}
		],
		"name": "upgradeToAndBumpVersion",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newImplementation",
				"type": "address"
			},
			{
				"internalType": "bytes",
				"name": "data",
				"type": "bytes"
			}
		],
		"name": "upgradeToAndCall",
		"outputs": [],
		"stateMutability": "payable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "to",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			}
		],
		"name": "withdrawToken",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "string",
				"name": "achievementId",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			}
		],
		"name": "checkIfAchievementRewarded",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "string",
				"name": "referralId",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "referredEoAddress",
				"type": "address"
			}
		],
		"name": "checkIfReferralRewarded",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "string",
				"name": "taskId",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "eoAddress",
				"type": "address"
			}
		],
		"name": "checkIfTaskRewarded",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "eip712Domain",
		"outputs": [
			{
				"internalType": "bytes1",
				"name": "fields",
				"type": "bytes1"
			},
			{
				"internalType": "string",
				"name": "name",
				"type": "string"
			},
			{
				"internalType": "string",
				"name": "version",
				"type": "string"
			},
			{
				"internalType": "uint256",
				"name": "chainId",
				"type": "uint256"
			},
			{
				"internalType": "address",
				"name": "verifyingContract",
				"type": "address"
			},
			{
				"internalType": "bytes32",
				"name": "salt",
				"type": "bytes32"
			},
			{
				"internalType": "uint256[]",
				"name": "extensions",
				"type": "uint256[]"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "token",
				"type": "address"
			}
		],
		"name": "getTokenBalance",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "goodDollarToken",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "isAchievementRewarded",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "isReferralRewarded",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "",
				"type": "bytes"
			}
		],
		"name": "isSignatureUsed",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "isTaskRewarded",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "isTaskRewardPaidToSmartAccount",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "owner",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "paused",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "proxiableUUID",
		"outputs": [
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "registry",
		"outputs": [
			{
				"internalType": "contract CanvassingWalletRegistry",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "signer",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "taskManager",
		"outputs": [
			{
				"internalType": "contract CanvassingTaskManager",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "totalAchievementRewards",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "totalReferralRewards",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "totalTaskRewards",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "totalDonationsFromRewards",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "UPGRADE_INTERFACE_VERSION",
		"outputs": [
			{
				"internalType": "string",
				"name": "",
				"type": "string"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "version",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	}
]