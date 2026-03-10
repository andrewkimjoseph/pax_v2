/// Global contract addresses used across the app.
/// Replace placeholder values with your deployed contract addresses per environment.
class ContractAddressConstants {
  ContractAddressConstants._();

  /// CanvassingTaskManager contract address.
  /// Used for screening balance checks and screening flow.
  static const String canvassingTaskManagerAddress =
      '0x339a7328289ef6f51be3f4d0Cb19cc46EB9eF4f1';

  /// CanvassingRewarder contract address.
  /// Used for task reward and achievement claim balance checks; rewards are paid from this contract.
  static const String canvassingRewarderAddress =
      '0x4D167933D742B31229bc730eADf5f2E3c4feceA2';
}
