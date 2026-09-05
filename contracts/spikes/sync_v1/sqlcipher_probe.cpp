// Isolated candidate probe, never linked into ExcellentCalendar production.
// Requires a NEW scratch DB path; does not open or migrate user databases.
#include <sqlite3.h>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

extern "C" int sqlite3_key_v2(sqlite3*, const char*, const void*, int);

constexpr const char* kSentinel = "SYNC_CT0_SYNTHETIC_TITLE_NOT_USER_DATA_123456789";
constexpr const char* kTestKey = "x'1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'";
constexpr const char* kWrongKey = "x'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890'";

void require(bool valid, const char* message) {
  if (!valid) throw std::runtime_error(message);
}

void exec(sqlite3* db, const char* sql) {
  require(sqlite3_exec(db, sql, nullptr, nullptr, nullptr) == SQLITE_OK, "SQL statement failed");
}

std::string scalar(sqlite3* db, const char* sql) {
  sqlite3_stmt* statement = nullptr;
  require(sqlite3_prepare_v2(db, sql, -1, &statement, nullptr) == SQLITE_OK, "Prepare failed");
  const int result = sqlite3_step(statement);
  std::string value;
  if (result == SQLITE_ROW) {
    const auto* bytes = sqlite3_column_text(statement, 0);
    if (bytes) value = reinterpret_cast<const char*>(bytes);
  }
  sqlite3_finalize(statement);
  require(result == SQLITE_ROW, "Expected scalar row");
  return value;
}

void assert_no_plaintext(const std::string& path) {
  std::ifstream stream(path, std::ios::binary);
  require(stream.good(), "Expected encrypted file is absent");
  const std::string bytes((std::istreambuf_iterator<char>(stream)), {});
  require(!bytes.empty(), "Expected encrypted file is empty");
  require(bytes.find(kSentinel) == std::string::npos, "Plaintext sentinel leaked");
}

int main(int argc, char** argv) {
  sqlite3* db = nullptr;
  try {
    require(argc == 2, "Supply a new scratch database path");
    const std::string path = argv[1];
    require(!std::filesystem::exists(path) && !std::filesystem::exists(path + "-wal") &&
                !std::filesystem::exists(path + "-shm"), "Refusing an existing path");
    const auto start = std::chrono::steady_clock::now();
    require(sqlite3_open_v2(path.c_str(), &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr) == SQLITE_OK, "Open failed");
    require(sqlite3_key_v2(db, "main", kTestKey, static_cast<int>(std::strlen(kTestKey))) == SQLITE_OK, "Key failed");
    require(std::string(sqlite3_libversion()) == "3.53.4", "SQLite baseline differs from frozen v5");
    const auto cipher = scalar(db, "PRAGMA cipher_version");
    require(cipher.rfind("4.18.0", 0) == 0, "Unexpected SQLCipher version");
    int defensive = 0;
    require(sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, 1, &defensive) == SQLITE_OK && defensive == 1, "Defensive mode unavailable");
    require(scalar(db, "PRAGMA journal_mode=WAL") == "wal", "WAL unavailable");
    exec(db, "PRAGMA synchronous=FULL");
    require(scalar(db, "PRAGMA synchronous") == "2", "FULL not enabled");
    exec(db, "PRAGMA wal_autocheckpoint=0");
    exec(db, "CREATE TABLE probe_facts(id INTEGER PRIMARY KEY, title TEXT NOT NULL)");
    exec(db, "BEGIN IMMEDIATE");
    sqlite3_stmt* insert = nullptr;
    require(sqlite3_prepare_v2(db, "INSERT INTO probe_facts VALUES(?,?)", -1, &insert, nullptr) == SQLITE_OK, "Insert prepare failed");
    for (int id = 1; id <= 20000; ++id) {
      sqlite3_bind_int(insert, 1, id);
      sqlite3_bind_text(insert, 2, kSentinel, -1, SQLITE_STATIC);
      require(sqlite3_step(insert) == SQLITE_DONE, "Insert failed");
      sqlite3_reset(insert);
    }
    sqlite3_finalize(insert);
    exec(db, "COMMIT");
    require(scalar(db, "SELECT count(*) FROM probe_facts") == "20000", "Row count mismatch");
    assert_no_plaintext(path);
    assert_no_plaintext(path + "-wal");
    require(sqlite3_close(db) == SQLITE_OK, "Close failed");
    db = nullptr;
    require(sqlite3_open_v2(path.c_str(), &db, SQLITE_OPEN_READWRITE, nullptr) == SQLITE_OK, "Reopen failed");
    require(sqlite3_key_v2(db, "main", kWrongKey, static_cast<int>(std::strlen(kWrongKey))) == SQLITE_OK, "Wrong-key setup failed unexpectedly");
    require(sqlite3_exec(db, "SELECT count(*) FROM probe_facts", nullptr, nullptr, nullptr) != SQLITE_OK, "Wrong key was accepted");
    sqlite3_close(db);
    db = nullptr;
    require(sqlite3_open_v2(path.c_str(), &db, SQLITE_OPEN_READWRITE, nullptr) == SQLITE_OK, "Correct-key reopen failed");
    require(sqlite3_key_v2(db, "main", kTestKey, static_cast<int>(std::strlen(kTestKey))) == SQLITE_OK, "Correct key failed");
    require(scalar(db, "SELECT count(*) FROM probe_facts") == "20000", "Reopen lost rows");
    require(scalar(db, "PRAGMA quick_check") == "ok", "Integrity check failed");
    sqlite3_close(db);
    db = nullptr;
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
    std::cout << "{\"rows\":20000,\"sqlite\":\"3.53.4\",\"cipher\":\"4.18.0\",\"wal\":true,\"full\":true,\"defensive\":true,\"wrong_key_rejected\":true,\"db_and_wal_sentinel_absent\":true,\"elapsed_ms\":" << elapsed << "}\n";
    return 0;
  } catch (const std::exception& error) {
    if (db) sqlite3_close(db);
    std::cerr << error.what() << '\n';
    return 1;
  }
}
