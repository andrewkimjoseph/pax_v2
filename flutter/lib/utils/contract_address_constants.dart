/// Global contract addresses used across the app.
/// Replace placeholder values with your deployed contract addresses per environment.
class ContractAddressConstants {
  ContractAddressConstants._();

  /// CanvassingTaskManager contract address.
  /// Used for screening balance checks and screening flow.
  /// Replace with the deployed address (e.g. from Firebase config or hardcoded per build).
  static const String canvassingTaskManagerAddress =
      '0x351df8260080CA47386442Bb19d4D025277bbAe3';

  /// CanvassingRewarder contract address.
  /// Used for task reward and achievement claim balance checks; rewards are paid from this contract.
  /// Replace with the deployed address.
  static const String canvassingRewarderAddress =
      '0xB439F45399d877447B1d140c90093f2DCC54c65c';
}
