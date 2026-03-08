import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class LocalDBHelper {
  static final LocalDBHelper _instance = LocalDBHelper._internal();
  factory LocalDBHelper() => _instance;
  LocalDBHelper._internal();

  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    String path;

    if (kIsWeb) {
      // Change default factory on the web
      databaseFactory = databaseFactoryFfiWeb;
      path = 'pax_balances_web.db';
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'pax_balances.db');
    }

    return await openDatabase(
      path,
      version: 7,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE balances (
            participantId TEXT NOT NULL,
            tokenId INTEGER NOT NULL,
            amount REAL NOT NULL,
            updatedAt INTEGER NOT NULL,
            PRIMARY KEY (participantId, tokenId)
          )
        ''');
        await db.execute('''
          CREATE TABLE wallet_balances (
            participantId TEXT PRIMARY KEY,
            goodDollarBalance REAL NOT NULL DEFAULT 0,
            celoDollarBalance REAL NOT NULL DEFAULT 0,
            tetherUsdBalance REAL NOT NULL DEFAULT 0,
            usdCoinBalance REAL NOT NULL DEFAULT 0,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE refreshments (
            participantId TEXT PRIMARY KEY,
            accountRefreshTime INTEGER,
            walletRefreshTime INTEGER,
            transactionsRefreshTime INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE pax_wallet_eoa_balances (
            participantId TEXT PRIMARY KEY,
            goodDollarBalance REAL NOT NULL DEFAULT 0,
            celoDollarBalance REAL NOT NULL DEFAULT 0,
            tetherUsdBalance REAL NOT NULL DEFAULT 0,
            usdCoinBalance REAL NOT NULL DEFAULT 0,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE wallet_transactions (
            eoAddress TEXT NOT NULL,
            hash TEXT NOT NULL,
            contractAddress TEXT NOT NULL DEFAULT '',
            blockNumber TEXT,
            timeStamp TEXT,
            "from" TEXT,
            "to" TEXT,
            value TEXT,
            gasUsed TEXT,
            gasPrice TEXT,
            functionName TEXT,
            isError TEXT,
            txreceipt_status TEXT,
            input TEXT,
            cumulativeGasUsed TEXT,
            confirmations TEXT,
            methodId TEXT,
            tokenName TEXT,
            tokenSymbol TEXT,
            tokenDecimal TEXT,
            updatedAt INTEGER NOT NULL,
            PRIMARY KEY (eoAddress, hash, contractAddress)
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE wallet_balances (
              participantId TEXT PRIMARY KEY,
              goodDollarBalance REAL NOT NULL DEFAULT 0,
              celoDollarBalance REAL NOT NULL DEFAULT 0,
              tetherUsdBalance REAL NOT NULL DEFAULT 0,
              usdCoinBalance REAL NOT NULL DEFAULT 0,
              updatedAt INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE refreshments (
              participantId TEXT PRIMARY KEY,
              accountRefreshTime INTEGER,
              walletRefreshTime INTEGER
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE pax_wallet_eoa_balances (
              participantId TEXT PRIMARY KEY,
              goodDollarBalance REAL NOT NULL DEFAULT 0,
              celoDollarBalance REAL NOT NULL DEFAULT 0,
              tetherUsdBalance REAL NOT NULL DEFAULT 0,
              usdCoinBalance REAL NOT NULL DEFAULT 0,
              updatedAt INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE refreshments ADD COLUMN transactionsRefreshTime INTEGER',
          );
          await db.execute('''
            CREATE TABLE wallet_transactions (
              eoAddress TEXT NOT NULL,
              hash TEXT NOT NULL,
              blockNumber TEXT,
              timeStamp TEXT,
              "from" TEXT,
              "to" TEXT,
              value TEXT,
              gasUsed TEXT,
              gasPrice TEXT,
              functionName TEXT,
              isError TEXT,
              txreceipt_status TEXT,
              input TEXT,
              contractAddress TEXT,
              cumulativeGasUsed TEXT,
              confirmations TEXT,
              methodId TEXT,
              updatedAt INTEGER NOT NULL,
              PRIMARY KEY (eoAddress, hash)
            )
          ''');
        }
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE wallet_transactions ADD COLUMN tokenName TEXT',
          );
          await db.execute(
            'ALTER TABLE wallet_transactions ADD COLUMN tokenSymbol TEXT',
          );
          await db.execute(
            'ALTER TABLE wallet_transactions ADD COLUMN tokenDecimal TEXT',
          );
        }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE wallet_transactions_new (
              eoAddress TEXT NOT NULL,
              hash TEXT NOT NULL,
              contractAddress TEXT NOT NULL DEFAULT '',
              blockNumber TEXT,
              timeStamp TEXT,
              "from" TEXT,
              "to" TEXT,
              value TEXT,
              gasUsed TEXT,
              gasPrice TEXT,
              functionName TEXT,
              isError TEXT,
              txreceipt_status TEXT,
              input TEXT,
              cumulativeGasUsed TEXT,
              confirmations TEXT,
              methodId TEXT,
              tokenName TEXT,
              tokenSymbol TEXT,
              tokenDecimal TEXT,
              updatedAt INTEGER NOT NULL,
              PRIMARY KEY (eoAddress, hash, contractAddress)
            )
          ''');
          await db.execute('DROP TABLE wallet_transactions');
          await db.execute(
            'ALTER TABLE wallet_transactions_new RENAME TO wallet_transactions',
          );
        }
      },
    );
  }

  Future<void> upsertBalance(
    String participantId,
    int tokenId,
    num amount,
  ) async {
    final dbClient = await db;
    await dbClient.insert('balances', {
      'participantId': participantId,
      'tokenId': tokenId,
      'amount': amount,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<int, num>> getBalances(String participantId) async {
    final dbClient = await db;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      'balances',
      where: 'participantId = ?',
      whereArgs: [participantId],
    );
    final Map<int, num> balances = {};
    for (final map in maps) {
      balances[map['tokenId'] as int] = map['amount'] as num;
    }
    return balances;
  }

  /// Returns the wallet's four currency balances from [wallet_balances] (one row per participant).
  /// Keys are token IDs: 1=Good Dollar, 2=Mento Dollar (USDm), 3=Tether USD, 4=USD Coin.
  Future<Map<int, num>> getWalletBalances(String participantId) async {
    final dbClient = await db;
    final List<Map<String, dynamic>> rows = await dbClient.query(
      'wallet_balances',
      where: 'participantId = ?',
      whereArgs: [participantId],
    );
    if (rows.isEmpty) {
      return {};
    }
    final row = rows.single;
    return {
      1: (row['goodDollarBalance'] as num?) ?? 0,
      2: (row['celoDollarBalance'] as num?) ?? 0,
      3: (row['tetherUsdBalance'] as num?) ?? 0,
      4: (row['usdCoinBalance'] as num?) ?? 0,
    };
  }

  /// Upserts the wallet's four currency balances into [wallet_balances].
  /// [balances] key is token ID (1–4), value is amount.
  Future<void> setWalletBalances(
    String participantId,
    Map<int, num> balances,
  ) async {
    final dbClient = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await dbClient.insert('wallet_balances', {
      'participantId': participantId,
      'goodDollarBalance': balances[1] ?? 0,
      'celoDollarBalance': balances[2] ?? 0,
      'tetherUsdBalance': balances[3] ?? 0,
      'usdCoinBalance': balances[4] ?? 0,
      'updatedAt': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns the Pax Wallet EOA four-currency balances from [pax_wallet_eoa_balances].
  /// Keys are token IDs: 1=Good Dollar, 2=Mento Dollar (USDm), 3=Tether USD, 4=USD Coin.
  Future<Map<int, num>> getPaxWalletEoaBalances(String participantId) async {
    final dbClient = await db;
    final List<Map<String, dynamic>> rows = await dbClient.query(
      'pax_wallet_eoa_balances',
      where: 'participantId = ?',
      whereArgs: [participantId],
    );
    if (rows.isEmpty) {
      return {};
    }
    final row = rows.single;
    return {
      1: (row['goodDollarBalance'] as num?) ?? 0,
      2: (row['celoDollarBalance'] as num?) ?? 0,
      3: (row['tetherUsdBalance'] as num?) ?? 0,
      4: (row['usdCoinBalance'] as num?) ?? 0,
    };
  }

  /// Upserts the Pax Wallet EOA four-currency balances into [pax_wallet_eoa_balances].
  Future<void> setPaxWalletEoaBalances(
    String participantId,
    Map<int, num> balances,
  ) async {
    final dbClient = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await dbClient.insert('pax_wallet_eoa_balances', {
      'participantId': participantId,
      'goodDollarBalance': balances[1] ?? 0,
      'celoDollarBalance': balances[2] ?? 0,
      'tetherUsdBalance': balances[3] ?? 0,
      'usdCoinBalance': balances[4] ?? 0,
      'updatedAt': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns the last refresh times for account and wallet for a participant, in epoch millis.
  /// Keys: 'accountRefreshTime', 'walletRefreshTime'. Empty map if no row.
  Future<Map<String, int?>> getRefreshments(String participantId) async {
    final dbClient = await db;
    final rows = await dbClient.query(
      'refreshments',
      where: 'participantId = ?',
      whereArgs: [participantId],
    );
    if (rows.isEmpty) {
      return {};
    }
    final row = rows.single;
    return {
      'accountRefreshTime': row['accountRefreshTime'] as int?,
      'walletRefreshTime': row['walletRefreshTime'] as int?,
      'transactionsRefreshTime': row['transactionsRefreshTime'] as int?,
    };
  }

  /// Upserts refresh timestamps for a participant. Provide only the field(s) you want to update.
  Future<void> upsertRefreshments({
    required String participantId,
    int? accountRefreshTime,
    int? walletRefreshTime,
    int? transactionsRefreshTime,
  }) async {
    final dbClient = await db;

    int? account = accountRefreshTime;
    int? wallet = walletRefreshTime;
    int? transactions = transactionsRefreshTime;

    final existing = await dbClient.query(
      'refreshments',
      where: 'participantId = ?',
      whereArgs: [participantId],
    );

    if (existing.isNotEmpty) {
      final row = existing.single;
      account ??= row['accountRefreshTime'] as int?;
      wallet ??= row['walletRefreshTime'] as int?;
      transactions ??= row['transactionsRefreshTime'] as int?;
    }

    // If all are still null, nothing to store.
    if (account == null && wallet == null && transactions == null) return;

    await dbClient.insert('refreshments', {
      'participantId': participantId,
      'accountRefreshTime': account,
      'walletRefreshTime': wallet,
      'transactionsRefreshTime': transactions,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns the last transactions list refresh time for a participant, in epoch millis, or null.
  Future<int?> getTransactionsRefreshTime(String participantId) async {
    final info = await getRefreshments(participantId);
    return info['transactionsRefreshTime'];
  }

  /// Sets the transactions list refresh time for a participant (preserves other refresh fields).
  Future<void> setTransactionsRefreshTime(
    String participantId,
    int epochMs,
  ) async {
    final info = await getRefreshments(participantId);
    await upsertRefreshments(
      participantId: participantId,
      accountRefreshTime: info['accountRefreshTime'],
      walletRefreshTime: info['walletRefreshTime'],
      transactionsRefreshTime: epochMs,
    );
  }

  /// Returns transactions for [eoAddress] from local DB, ordered by timeStamp DESC.
  /// [limit] and [offset] default to 50 and 0.
  Future<List<Map<String, dynamic>>> getWalletTransactions(
    String eoAddress, {
    int limit = 50,
    int offset = 0,
  }) async {
    final dbClient = await db;
    final rows = await dbClient.query(
      'wallet_transactions',
      where: 'eoAddress = ?',
      whereArgs: [eoAddress],
      orderBy: 'timeStamp DESC',
      limit: limit,
      offset: offset,
    );
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Replaces all stored transactions for [eoAddress] with [transactions].
  /// Each map should include: hash, blockNumber, timeStamp, from, to, value, gasUsed, gasPrice, functionName, isError, txreceipt_status, input, etc.
  Future<void> upsertWalletTransactions(
    String eoAddress,
    List<Map<String, dynamic>> transactions,
  ) async {
    final dbClient = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await dbClient.delete(
      'wallet_transactions',
      where: 'eoAddress = ?',
      whereArgs: [eoAddress],
    );
    for (final tx in transactions) {
      final hash = tx['hash'] as String?;
      if (hash == null || hash.isEmpty) continue;
      final contractAddress = tx['contractAddress']?.toString().trim() ?? '';
      await dbClient.insert('wallet_transactions', {
        'eoAddress': eoAddress,
        'hash': hash,
        'contractAddress': contractAddress,
        'blockNumber': tx['blockNumber']?.toString(),
        'timeStamp': tx['timeStamp']?.toString(),
        'from': tx['from']?.toString(),
        'to': tx['to']?.toString(),
        'value': tx['value']?.toString(),
        'gasUsed': tx['gasUsed']?.toString(),
        'gasPrice': tx['gasPrice']?.toString(),
        'functionName': tx['functionName']?.toString(),
        'isError': tx['isError']?.toString(),
        'txreceipt_status': tx['txreceipt_status']?.toString(),
        'input': tx['input']?.toString(),
        'cumulativeGasUsed': tx['cumulativeGasUsed']?.toString(),
        'confirmations': tx['confirmations']?.toString(),
        'methodId': tx['methodId']?.toString(),
        'tokenName': tx['tokenName']?.toString(),
        'tokenSymbol': tx['tokenSymbol']?.toString(),
        'tokenDecimal': tx['tokenDecimal']?.toString(),
        'updatedAt': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> clearBalances(String participantId) async {
    final dbClient = await db;
    await dbClient.delete(
      'balances',
      where: 'participantId = ?',
      whereArgs: [participantId],
    );
    await dbClient.delete(
      'wallet_balances',
      where: 'participantId = ?',
      whereArgs: [participantId],
    );
    await dbClient.delete(
      'pax_wallet_eoa_balances',
      where: 'participantId = ?',
      whereArgs: [participantId],
    );
  }
}
