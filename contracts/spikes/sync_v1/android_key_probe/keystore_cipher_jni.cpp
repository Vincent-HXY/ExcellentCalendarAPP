// Disposable APK encryption feasibility. Uses the same pinned native SQLCipher
// libraries as the source spike. These experiment tables are not storage v6.
#include <jni.h>
#define SQLITE_HAS_CODEC
#include <sqlite3.h>
#include <array>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace {
struct Database { sqlite3* db = nullptr; ~Database() { if (db) sqlite3_close_v2(db); } };
struct Statement { sqlite3_stmt* value = nullptr; ~Statement() { if (value) sqlite3_finalize(value); } };
struct Utf { JNIEnv* env; jstring source; const char* value; Utf(JNIEnv* e, jstring s):env(e),source(s),value(e->GetStringUTFChars(s,nullptr)){}
    ~Utf(){ if(value) env->ReleaseStringUTFChars(source,value); } };
bool execute(sqlite3* db, const char* sql) { return sqlite3_exec(db,sql,nullptr,nullptr,nullptr) == SQLITE_OK; }
bool scalar(sqlite3* db,const char* sql,const char* expected) {
    Statement statement;
    return sqlite3_prepare_v2(db,sql,-1,&statement.value,nullptr)==SQLITE_OK && sqlite3_step(statement.value)==SQLITE_ROW &&
        sqlite3_column_type(statement.value,0)!=SQLITE_NULL && std::string(reinterpret_cast<const char*>(sqlite3_column_text(statement.value,0)))==expected;
}
void clear(std::array<unsigned char,32>& key) { volatile unsigned char* p=key.data(); for(std::size_t i=0;i<key.size();++i) p[i]=0; }
}

extern "C" JNIEXPORT jint JNICALL Java_com_excellentcalendar_contractspike_SyncStorageInstrumentation_nativeDatabase(
    JNIEnv* env,jclass,jstring path,jbyteArray key,jboolean create,jstring account,jstring workspace) {
    if(!path || !key || !account || !workspace || env->GetArrayLength(key)!=32) return 1;
    Utf file(env,path),owner(env,account),space(env,workspace);
    if(env->ExceptionCheck() || !file.value || !owner.value || !space.value) { env->ExceptionClear(); return 2; }
    Database connection;
    if(sqlite3_open_v2(file.value,&connection.db,SQLITE_OPEN_READWRITE | (create?SQLITE_OPEN_CREATE:0),nullptr)!=SQLITE_OK) return 3;
    std::array<unsigned char,32> material{};
    env->GetByteArrayRegion(key,0,32,reinterpret_cast<jbyte*>(material.data()));
    if(env->ExceptionCheck()) { env->ExceptionClear(); clear(material); return 4; }
    const int keyed=sqlite3_key(connection.db,material.data(),32); clear(material);
    if(keyed!=SQLITE_OK) return 5;
    int enabled=0;
    if(sqlite3_db_config(connection.db,SQLITE_DBCONFIG_DEFENSIVE,1,&enabled)!=SQLITE_OK || enabled!=1) return 6;
    if(!scalar(connection.db,"PRAGMA cipher_version","4.18.0 community")) return 7;
    if(!execute(connection.db,"PRAGMA foreign_keys=ON;PRAGMA journal_mode=WAL;PRAGMA synchronous=FULL;PRAGMA temp_store=MEMORY;")) return 8;
    if(create) {
        if(!execute(connection.db,"BEGIN IMMEDIATE;CREATE TABLE spike_binding(account_id TEXT NOT NULL,workspace_id TEXT NOT NULL,profile TEXT NOT NULL);"
            "CREATE TABLE spike_rows(id INTEGER PRIMARY KEY,title TEXT NOT NULL,revision INTEGER NOT NULL);")) return 9;
        Statement binding;
        if(sqlite3_prepare_v2(connection.db,"INSERT INTO spike_binding VALUES(?,?,'account_sqlcipher_v1')",-1,&binding.value,nullptr)!=SQLITE_OK) return 10;
        sqlite3_bind_text(binding.value,1,owner.value,-1,SQLITE_TRANSIENT); sqlite3_bind_text(binding.value,2,space.value,-1,SQLITE_TRANSIENT);
        if(sqlite3_step(binding.value)!=SQLITE_DONE) return 11;
        Statement insert;
        if(sqlite3_prepare_v2(connection.db,"INSERT INTO spike_rows VALUES(?,?,9007199254740991)",-1,&insert.value,nullptr)!=SQLITE_OK) return 12;
        for(int i=0;i<20000;++i) {
            sqlite3_bind_int(insert.value,1,i); const auto title=std::string("EC_KEYSTORE_PRIVATE_SENTINEL_")+std::to_string(i);
            sqlite3_bind_text(insert.value,2,title.c_str(),static_cast<int>(title.size()),SQLITE_TRANSIENT);
            if(sqlite3_step(insert.value)!=SQLITE_DONE || sqlite3_reset(insert.value)!=SQLITE_OK) return 13;
        }
        if(!execute(connection.db,"COMMIT")) return 14;
    }
    Statement binding;
    if(sqlite3_prepare_v2(connection.db,"SELECT account_id,workspace_id,profile FROM spike_binding",-1,&binding.value,nullptr)!=SQLITE_OK || sqlite3_step(binding.value)!=SQLITE_ROW) return 15;
    if(std::string(reinterpret_cast<const char*>(sqlite3_column_text(binding.value,0)))!=owner.value ||
       std::string(reinterpret_cast<const char*>(sqlite3_column_text(binding.value,1)))!=space.value ||
       std::string(reinterpret_cast<const char*>(sqlite3_column_text(binding.value,2)))!="account_sqlcipher_v1") return 16;
    if(!scalar(connection.db,"SELECT count(*) FROM spike_rows","20000") || !scalar(connection.db,"SELECT max(revision) FROM spike_rows","9007199254740991")) return 17;
    if(!scalar(connection.db,"PRAGMA integrity_check","ok")) return 18;
    // Even while WAL is live, plaintext business markers must not occur in any
    // on-disk database/WAL/SHM file. This does not claim physical memory erasure.
    for(const auto& suffix : {"","-wal","-shm"}) {
        std::ifstream input(std::string(file.value)+suffix,std::ios::binary);
        std::string bytes((std::istreambuf_iterator<char>(input)),std::istreambuf_iterator<char>());
        if(bytes.find("EC_KEYSTORE_PRIVATE_SENTINEL_")!=std::string::npos || bytes.rfind("SQLite format 3",0)==0) return 19;
    }
    return 0;
}
