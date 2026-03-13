# Deploy: sponsored achievement claims

`claimAchievementReward` now requires `msg.sender == smartAccountContractAddress` (same as task rewards). **Upgrade the CanvassingRewarder implementation via UUPS before** deploying Cloud Functions that call the new V2 achievement path.

1. Deploy new `CanvassingRewarder` implementation.
2. Call `upgradeToAndCall` on the existing proxy (owner), pointing at the new implementation.
3. Deploy Firebase functions (`processAchievementClaim`, `rewardParticipantProxy` use shared Pimlico helper; behavior unchanged for task claims except shared code path).

Until the proxy is upgraded, sponsored achievement userOps will revert on-chain if the old rule (`msg.sender == eoAddress`) is still active.
