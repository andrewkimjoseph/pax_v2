class CurrencySymbolUtil {
  /// Returns the currency symbol for a given currency label
  static String getSymbolForCurrency(String currencyLabel) {
    final key = currencyLabel.toLowerCase();
    if (key == 'celo_dollar') return 'USDm';
    switch (key) {
      case 'good_dollar':
        return 'G\$';
      case 'usdm':
        return 'USDm';
      case 'tether_usd':
        return 'USDT';
      case 'usd_coin':
        return 'USDC';
      default:
        return currencyLabel;
    }
  }

  /// Returns the asset path for an SVG icon for the given Etherscan token symbol
  /// (e.g. from ERC-20 tokentx: "G\$", "USD₮", "CELO", "USDm"). Returns null if no asset.
  static String? getCurrencyAssetPathForTokenSymbol(String? tokenSymbol) {
    if (tokenSymbol == null || tokenSymbol.isEmpty) return null;
    final s = tokenSymbol.trim();
    if (_isTetherSymbol(s)) return 'lib/assets/svgs/currencies/tether_usd.svg';
    switch (s) {
      case 'G\$':
        return 'lib/assets/svgs/currencies/good_dollar.svg';
      case 'USD₮':
      case 'USDT':
        return 'lib/assets/svgs/currencies/tether_usd.svg';
      case 'CELO':
        return 'lib/assets/svgs/celo.svg';
      case 'USDm':
        return 'lib/assets/svgs/currencies/usdm.svg';
      case 'USDC':
        return 'lib/assets/svgs/currencies/usd_coin.svg';
      case 'cUSD':
        return 'lib/assets/svgs/currencies/usdm.svg';
      default:
        return null;
    }
  }

  /// Returns a display-safe symbol for the given token symbol from API/blockchain.
  /// Use this when showing the symbol in UI so unsupported characters (e.g. Tether's ₮) show as "USDT".
  static String getDisplaySymbolForTokenSymbol(String? tokenSymbol) {
    if (tokenSymbol == null || tokenSymbol.isEmpty) return tokenSymbol ?? '';
    final s = tokenSymbol.trim();
    // Tether often comes as "USD₮" (Unicode ₮) which can render as a square; use ASCII "USDT".
    if (s == 'USD₮' || s.toUpperCase() == 'USDT' || _isTetherSymbol(s)) {
      return 'USDT';
    }
    return s;
  }

  static bool _isTetherSymbol(String s) {
    if (s.length < 4) return false;
    final upper = s.toUpperCase();
    if (upper == 'USDM') return false; // Mento Dollar
    if (upper.startsWith('USD') && (upper.endsWith('T') || s.endsWith('₮'))) {
      return true;
    }
    // Catch "USD" + unsupported/variant T character (e.g. renders as square).
    if (s.length == 4 && upper.startsWith('USD')) return true;
    return false;
  }

  /// Known ERC-20 token contract addresses (Celo) -> currency asset path.
  /// [contractAddress] from Etherscan tokentx is the token contract, not the tx receiver.
  static const Map<String, String> _tokenContractToAssetPath = {
    '0x62b8b11039fcfe5ab0c56e502b1c372a3d2a9c7a':
        'lib/assets/svgs/currencies/good_dollar.svg',
    '0x765de816845861e75a25fca122bb6898b8b1282a':
        'lib/assets/svgs/currencies/usdm.svg',
    '0x48065fbbe25f71c9282ddf5e1cd6d6a887483d5e':
        'lib/assets/svgs/currencies/tether_usd.svg',
    '0xceba9300f2b948710d2653dd7b07f33a8b32118c':
        'lib/assets/svgs/currencies/usd_coin.svg',
    '0x471ece3750da237f93b8e339c536989b8978a438': 'lib/assets/svgs/celo.svg',
  };

  /// Returns the asset path for the token's SVG icon using [contractAddress] from
  /// ERC-20 tokentx (the token contract address). Returns null if unknown.
  static String? getCurrencyAssetPathForTokenContract(String? contractAddress) {
    if (contractAddress == null || contractAddress.isEmpty) return null;
    return _tokenContractToAssetPath[contractAddress.trim().toLowerCase()];
  }

  static String getNameForCurrency(int? tokenId) {
    switch (tokenId) {
      case 1:
        return "good_dollar";
      case 2:
        return 'usdm';
      case 3:
        return 'tether_usd';
      case 4:
        return 'usd_coin';
      default:
        return "good_dollar";
    }
  }
}
