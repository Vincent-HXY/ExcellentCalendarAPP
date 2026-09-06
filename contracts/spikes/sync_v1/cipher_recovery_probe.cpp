// Isolated real-file SQLCipher fault probe. Only opens synthetic scratch databases.
// VFS faults simulate SQLITE_FULL; SIGKILL/TerminateProcess is an actual process kill.
#include <sqlite3.h>
#include <cstddef>
#include <csignal>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#ifdef _WIN32
#include <windows.h>
#endif

extern "C" int sqlite3_key_v2(sqlite3*, const char*, const void*, int);
namespace {
constexpr char key[] = "x'0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'";
constexpr char other_key[] = "x'1123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'";
constexpr char sentinel[] = "SYNC_SYNTHETIC_RECOVERY_PAYLOAD_0123456789";
sqlite3_vfs* original_vfs;
enum class Fault { none, full, wal_sync_kill, checkpoint_kill };
Fault fault = Fault::none;
int writes = 0, temp_opens = 0;
bool fault_hit = false;
struct File { sqlite3_file base; sqlite3_file* real; int flags; };
constexpr auto prefix = (sizeof(File) + alignof(std::max_align_t) - 1) /
    alignof(std::max_align_t) * alignof(std::max_align_t);
File* file(sqlite3_file* f) { return reinterpret_cast<File*>(f); }
void require(bool ok, const char* reason) { if (!ok) throw std::runtime_error(reason); }
[[noreturn]] void kill_now() {
  std::cout << "KILL_POINT_REACHED\n" << std::flush;
#ifdef _WIN32
  TerminateProcess(GetCurrentProcess(), 86);
#else
  std::raise(SIGKILL);
#endif
  std::_Exit(87);
}
int close_file(sqlite3_file* f) { auto* r = file(f)->real; return r->pMethods->xClose(r); }
int read_file(sqlite3_file* f, void* p, int n, sqlite3_int64 o) { auto* r = file(f)->real; return r->pMethods->xRead(r,p,n,o); }
int write_file(sqlite3_file* f, const void* p, int n, sqlite3_int64 o) {
  auto* w = file(f); auto* r = w->real;
  if (fault == Fault::full && ++writes == 2) { fault_hit = true; return SQLITE_FULL; }
  if (fault == Fault::checkpoint_kill && (w->flags & SQLITE_OPEN_MAIN_DB) && ++writes == 5) kill_now();
  return r->pMethods->xWrite(r,p,n,o);
}
int truncate_file(sqlite3_file* f, sqlite3_int64 n) { auto* r=file(f)->real; return r->pMethods->xTruncate(r,n); }
int sync_file(sqlite3_file* f, int flags) {
  auto* w = file(f); auto* r = w->real;
  if (fault == Fault::wal_sync_kill && (w->flags & SQLITE_OPEN_WAL)) kill_now();
  return r->pMethods->xSync(r,flags);
}
int size_file(sqlite3_file* f, sqlite3_int64* n) { auto* r=file(f)->real; return r->pMethods->xFileSize(r,n); }
int lock_file(sqlite3_file* f, int v) { auto* r=file(f)->real; return r->pMethods->xLock(r,v); }
int unlock_file(sqlite3_file* f, int v) { auto* r=file(f)->real; return r->pMethods->xUnlock(r,v); }
int reserved_file(sqlite3_file* f, int* v) { auto* r=file(f)->real; return r->pMethods->xCheckReservedLock(r,v); }
int control_file(sqlite3_file* f, int n, void* p) { auto* r=file(f)->real; return r->pMethods->xFileControl(r,n,p); }
int sector_file(sqlite3_file* f) { auto* r=file(f)->real; return r->pMethods->xSectorSize(r); }
int device_file(sqlite3_file* f) { auto* r=file(f)->real; return r->pMethods->xDeviceCharacteristics(r); }
int map_file(sqlite3_file* f,int a,int b,int c,void volatile** p) { auto* r=file(f)->real; return r->pMethods->xShmMap(r,a,b,c,p); }
int shm_lock(sqlite3_file* f,int a,int b,int c) { auto* r=file(f)->real; return r->pMethods->xShmLock(r,a,b,c); }
void barrier(sqlite3_file* f) { auto* r=file(f)->real; r->pMethods->xShmBarrier(r); }
int unmap(sqlite3_file* f,int a) { auto* r=file(f)->real; return r->pMethods->xShmUnmap(r,a); }
int fetch(sqlite3_file* f,sqlite3_int64 o,int n,void** p) {
  auto* r=file(f)->real; if (!r->pMethods->xFetch) { *p=nullptr; return SQLITE_OK; } return r->pMethods->xFetch(r,o,n,p);
}
int unfetch(sqlite3_file* f,sqlite3_int64 o,void* p) { auto* r=file(f)->real; return r->pMethods->xUnfetch ? r->pMethods->xUnfetch(r,o,p) : SQLITE_OK; }
const sqlite3_io_methods methods = {3,close_file,read_file,write_file,truncate_file,sync_file,size_file,
  lock_file,unlock_file,reserved_file,control_file,sector_file,device_file,map_file,shm_lock,barrier,unmap,fetch,unfetch};
int open_file(sqlite3_vfs*,const char* name,sqlite3_file* f,int flags,int* actual) {
  auto* w=file(f); w->real=reinterpret_cast<sqlite3_file*>(reinterpret_cast<char*>(f)+prefix); w->flags=flags;
  const int result=original_vfs->xOpen(original_vfs,name,w->real,flags,actual);
  if (result==SQLITE_OK) {
    w->base.pMethods=&methods;
    if (!name || (flags & (SQLITE_OPEN_DELETEONCLOSE|SQLITE_OPEN_TEMP_DB|SQLITE_OPEN_TEMP_JOURNAL|SQLITE_OPEN_SUBJOURNAL))) ++temp_opens;
  }
  return result;
}
void install_vfs() {
  original_vfs=sqlite3_vfs_find(nullptr); require(original_vfs,"No native VFS");
  static sqlite3_vfs wrapper=*original_vfs;
  wrapper.zName="sync-synthetic-fault-vfs"; wrapper.szOsFile=static_cast<int>(prefix)+original_vfs->szOsFile;
  wrapper.xOpen=open_file;
  require(sqlite3_vfs_register(&wrapper,0)==SQLITE_OK,"Cannot install fault VFS");
}
void exec(sqlite3* db,const char* sql) { require(sqlite3_exec(db,sql,nullptr,nullptr,nullptr)==SQLITE_OK,"SQL failed"); }
std::string scalar(sqlite3* db,const char* sql) {
  sqlite3_stmt* s=nullptr;
  require(sqlite3_prepare_v2(db,sql,-1,&s,nullptr)==SQLITE_OK,"Prepare failed");
  const int step=sqlite3_step(s); std::string value;
  if (step==SQLITE_ROW && sqlite3_column_text(s,0)) value=reinterpret_cast<const char*>(sqlite3_column_text(s,0));
  sqlite3_finalize(s); require(step==SQLITE_ROW,"Expected scalar"); return value;
}
sqlite3* open(const std::string& path,bool create=false,const char* supplied_key=key) {
  sqlite3* db=nullptr;
  require(sqlite3_open_v2(path.c_str(),&db,SQLITE_OPEN_READWRITE|(create?SQLITE_OPEN_CREATE:0),"sync-synthetic-fault-vfs")==SQLITE_OK,"Open failed");
  if (supplied_key) require(sqlite3_key_v2(db,"main",supplied_key,static_cast<int>(std::strlen(supplied_key)))==SQLITE_OK,"Key setup failed");
  return db;
}
sqlite3* open_bound(const std::string& path,const char* workspace,const char* account,const char* profile) {
  auto* db=open(path);
  sqlite3_stmt* s=nullptr;
  require(sqlite3_prepare_v2(db,"SELECT count(*) FROM metadata WHERE workspace=? AND account_binding=? AND profile=?",-1,&s,nullptr)==SQLITE_OK,"Binding query failed");
  sqlite3_bind_text(s,1,workspace,-1,SQLITE_TRANSIENT);
  sqlite3_bind_text(s,2,account,-1,SQLITE_TRANSIENT);
  sqlite3_bind_text(s,3,profile,-1,SQLITE_TRANSIENT);
  const bool matches=sqlite3_step(s)==SQLITE_ROW && sqlite3_column_int(s,0)==1;
  sqlite3_finalize(s);
  if (!matches) { require(sqlite3_close(db)==SQLITE_OK,"Rejected binding close failed"); return nullptr; }
  return db;
}
void binary_key_roundtrip(const std::string& path) {
  require(!std::filesystem::exists(path),"Refusing an existing binary-key DB");
  unsigned char binary[32]; for (int i=0;i<32;++i) binary[i]=static_cast<unsigned char>(i*7);
  require(binary[0]==0,"Fixture must exercise embedded NUL");
  for (int attempt=0;attempt<3;++attempt) {
    sqlite3* db=nullptr;
    require(sqlite3_open_v2(path.c_str(),&db,SQLITE_OPEN_READWRITE|(attempt==0?SQLITE_OPEN_CREATE:0),nullptr)==SQLITE_OK,"Binary key open failed");
    require(sqlite3_key_v2(db,"main",binary,attempt==1?31:32)==SQLITE_OK,"Binary key setup failed");
    if (attempt==0) exec(db,"CREATE TABLE binary_key_fact(value TEXT NOT NULL); INSERT INTO binary_key_fact VALUES('synthetic binary key roundtrip')");
    else if (attempt==1) require(sqlite3_exec(db,"SELECT * FROM binary_key_fact",nullptr,nullptr,nullptr)!=SQLITE_OK,"Wrong binary length accepted");
    else require(scalar(db,"SELECT value FROM binary_key_fact")=="synthetic binary key roundtrip","Binary key roundtrip failed");
    require(sqlite3_close(db)==SQLITE_OK,"Binary key close failed");
  }
}
void policy(sqlite3* db) {
  int enabled=0;
  require(sqlite3_db_config(db,SQLITE_DBCONFIG_DEFENSIVE,1,&enabled)==SQLITE_OK && enabled,"Defensive failed");
  require(scalar(db,"PRAGMA journal_mode=WAL")=="wal","WAL failed");
  exec(db,"PRAGMA synchronous=FULL; PRAGMA wal_autocheckpoint=0; PRAGMA temp_store=MEMORY; PRAGMA cache_size=64; PRAGMA mmap_size=0");
}
void initialize(const std::string& path) {
  require(!std::filesystem::exists(path) && !std::filesystem::exists(path+"-wal") && !std::filesystem::exists(path+"-shm"),"Refusing existing scratch DB");
  auto* db=open(path,true); policy(db);
  exec(db,"CREATE TABLE facts(id INTEGER PRIMARY KEY, version INTEGER NOT NULL, title TEXT NOT NULL);"
    "CREATE TABLE outbox(id INTEGER PRIMARY KEY, version INTEGER NOT NULL);"
    "CREATE TABLE metadata(workspace TEXT NOT NULL, account_binding TEXT NOT NULL, profile TEXT NOT NULL);"
    "INSERT INTO metadata VALUES('synthetic-workspace','synthetic-account','sqlcipher4-ltc-v1'); BEGIN IMMEDIATE");
  sqlite3_stmt* s=nullptr;
  require(sqlite3_prepare_v2(db,"INSERT INTO facts VALUES(?,0,?)",-1,&s,nullptr)==SQLITE_OK,"Prepare failed");
  for (int id=1;id<=20000;++id) {
    sqlite3_bind_int(s,1,id); sqlite3_bind_text(s,2,sentinel,-1,SQLITE_STATIC);
    require(sqlite3_step(s)==SQLITE_DONE,"Seed failed"); sqlite3_reset(s);
  }
  sqlite3_finalize(s); exec(db,"COMMIT; PRAGMA wal_checkpoint(TRUNCATE)");
  require(sqlite3_close(db)==SQLITE_OK,"Close failed");
}
void update(sqlite3* db) {
  exec(db,"BEGIN IMMEDIATE; UPDATE facts SET version=1; INSERT INTO outbox SELECT id,version FROM facts");
}
void verify(sqlite3* db,const std::string& expected) {
  require(scalar(db,"PRAGMA integrity_check")=="ok","Integrity failure");
  require(scalar(db,"SELECT count(*) FROM facts")=="20000","Lost facts");
  const auto changed=scalar(db,"SELECT count(*) FROM facts WHERE version=1");
  require(changed=="0" || changed=="20000","Partial business transaction");
  require(scalar(db,"SELECT count(*) FROM outbox")==changed,"Facts and outbox split");
  if (expected!="either") require(changed==expected,"Wrong recovered commit");
}
void no_plaintext(const std::string& path) {
  std::ifstream in(path,std::ios::binary); require(in.good(),"Missing encrypted file");
  const std::string bytes((std::istreambuf_iterator<char>(in)),{});
  require(!bytes.empty() && bytes.find(sentinel)==std::string::npos,"Plaintext leaked");
}
} // namespace
int main(int argc,char** argv) {
  try {
    require(argc>=3,"Supply mode and a synthetic scratch DB");
    const std::string mode=argv[1],path=argv[2]; install_vfs();
    if (mode=="init") initialize(path);
    else if (mode=="binary-key") binary_key_roundtrip(path);
    else if (mode=="keys") {
      for (const char* bad : {static_cast<const char*>(nullptr),other_key}) {
        auto* db=open(path,false,bad);
        require(sqlite3_exec(db,"SELECT * FROM metadata",nullptr,nullptr,nullptr)!=SQLITE_OK,"Missing/wrong key accepted");
        require(sqlite3_close(db)==SQLITE_OK,"Close failed");
      }
      auto* db=open(path); exec(db,"PRAGMA cipher_page_size=8192");
      require(sqlite3_exec(db,"SELECT * FROM metadata",nullptr,nullptr,nullptr)!=SQLITE_OK,"Wrong cipher profile accepted");
      sqlite3_close(db);
      require(open_bound(path,"other","synthetic-account","sqlcipher4-ltc-v1")==nullptr,"Wrong workspace opened");
      require(open_bound(path,"synthetic-workspace","other","sqlcipher4-ltc-v1")==nullptr,"Wrong account opened");
      require(open_bound(path,"synthetic-workspace","synthetic-account","other")==nullptr,"Wrong metadata profile opened");
      db=open_bound(path,"synthetic-workspace","synthetic-account","sqlcipher4-ltc-v1");
      require(db!=nullptr,"Valid binding rejected");
      verify(db,"0"); sqlite3_close(db);
    } else {
      auto* db=open(path); policy(db);
      if (mode=="verify") { require(argc==4,"Expected recovery count"); verify(db,argv[3]); }
      else if (mode=="kill-before-commit") { update(db); kill_now(); }
      else if (mode=="kill-during-wal-sync") { update(db); fault=Fault::wal_sync_kill; exec(db,"COMMIT"); throw std::runtime_error("WAL kill was not reached"); }
      else if (mode=="kill-after-commit") { update(db); exec(db,"COMMIT"); kill_now(); }
      else if (mode=="kill-during-checkpoint") { update(db); exec(db,"COMMIT"); fault=Fault::checkpoint_kill; exec(db,"PRAGMA wal_checkpoint(TRUNCATE)"); throw std::runtime_error("Checkpoint kill was not reached"); }
      else if (mode=="full") {
        fault=Fault::full;
        const auto rc=sqlite3_exec(db,"BEGIN IMMEDIATE; UPDATE facts SET version=1; INSERT INTO outbox SELECT id,version FROM facts; COMMIT",nullptr,nullptr,nullptr);
        fault=Fault::none;
        require(rc==SQLITE_FULL && fault_hit,"Injected FULL was not reported");
        sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr); verify(db,"0");
      } else if (mode=="temp") {
        require(scalar(db,"PRAGMA temp_store")=="2","Memory temp policy lost");
        exec(db,"CREATE TEMP TABLE sorted AS SELECT * FROM facts ORDER BY title DESC,id DESC");
        require(scalar(db,"SELECT count(*) FROM sorted")=="20000","Temp sort failed");
        update(db); exec(db,"COMMIT"); verify(db,"20000");
        no_plaintext(path); no_plaintext(path+"-wal");
        require(temp_opens==0,"Temporary file opened despite policy");
      } else throw std::runtime_error("Unknown mode");
      require(sqlite3_close(db)==SQLITE_OK,"Close failed");
    }
    std::cout << "{\"mode\":\"" << mode << "\",\"passed\":true,\"rows\":20000,\"temporary_file_opens\":" << temp_opens << "}\n";
    return 0;
  } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
