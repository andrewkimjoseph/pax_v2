/// Global contract addresses used across the app.
/// Replace placeholder values with your deployed contract addresses per environment.
class ContractAddressConstants {
  ContractAddressConstants._();

  /// CanvassingRewarder contract address.
  /// Used for task reward and achievement claim balance checks; rewards are paid from this contract.
  static const String canvassingRewarderProxyAddress =
      '0x4D167933D742B31229bc730eADf5f2E3c4feceA2';
}
