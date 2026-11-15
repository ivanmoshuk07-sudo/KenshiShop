#pragma once
// Minimal KenshiLib hook adapter. All addresses come from public exports and
// GetRealAddress. Registry operations are thread-safe; hooks never call Lua.
#include <unordered_map>
#include <cstdint>
#include <cstring>
namespace KSNoSever {
struct Vec3 {float x,y,z;};
typedef void(__fastcall* AmputateFn)(void*,int,bool,const Vec3&);
typedef void(__fastcall* CrushFn)(void*,int);
typedef void(__fastcall* DestroyFn)(void*);
typedef void(__fastcall* RaceFn)(void*,void*);
typedef intptr_t(__cdecl* AddressFn)(void*);
typedef int(__cdecl* HookFn)(void*,void*,void**);
static AmputateFn originalAmputate=NULL;
static CrushFn originalCrush=NULL;
static DestroyFn originalDestroy=NULL;
static RaceFn originalRace=NULL;
struct Protection {int race; unsigned long long amputations,crushes;};
static SRWLOCK registryLock=SRWLOCK_INIT;
static std::unordered_map<void*,Protection> registry;
static bool hooksReady=false;
static bool destroyReady=false,raceReady=false,crushReady=false,amputateReady=false;
static bool block(void* med,int limb,bool crush) {
 if(limb<0||limb>3)return false;
 AcquireSRWLockExclusive(&registryLock);
 auto found=registry.find(med);bool protectedActor=found!=registry.end();
 if(protectedActor) {
  if(crush)++found->second.crushes;else ++found->second.amputations;
 }
 ReleaseSRWLockExclusive(&registryLock);
 return protectedActor;
}
static void forget(void* med) {
 AcquireSRWLockExclusive(&registryLock);registry.erase(med);ReleaseSRWLockExclusive(&registryLock);
}
static void __fastcall onAmputate(void* med,int limb,bool create,const Vec3& force) {
 if(!block(med,limb,false))originalAmputate(med,limb,create,force);
}
static void __fastcall onCrush(void* med,int limb) {
 if(!block(med,limb,true))originalCrush(med,limb);
}
static void __fastcall onDestroy(void* med) {
 forget(med);originalDestroy(med);
}
static void __fastcall onRaceChange(void* med,void* race) {
 forget(med);originalRace(med,race);
}
static bool installOne(HMODULE lib,AddressFn address,HookFn add,const char* symbol,void* detour,void** original,bool& installed) {
 if(installed)return true;
 FARPROC stub=GetProcAddress(lib,symbol);if(!stub)return false;
 void* target=reinterpret_cast<void*>(address(reinterpret_cast<void*>(stub)));
 if(!target)return false;
 installed=add(target,detour,original)==0 && *original!=NULL;return installed;
}
static bool install() {
 if(hooksReady)return true;
 HMODULE lib=GetModuleHandleA("KenshiLib.dll");if(!lib)return false;
 auto address=reinterpret_cast<AddressFn>(GetProcAddress(lib,"?GetRealAddress@KenshiLib@@YA_JPEAX@Z"));
 auto add=reinterpret_cast<HookFn>(GetProcAddress(lib,"?AddHook@KenshiLib@@YA?AW4HookStatus@1@PEAX0PEAPEAX@Z"));
 if(!address||!add)return false;
 // Native detours outlive the Lua state. Pin our module before installing any.
 HMODULE pinned=NULL;
 if(!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
   reinterpret_cast<LPCSTR>(&onAmputate),&pinned))return false;
 if(!installOne(lib,address,add,"?_DESTRUCTOR@MedicalSystem@@QEAAXXZ",reinterpret_cast<void*>(&onDestroy),reinterpret_cast<void**>(&originalDestroy),destroyReady))return false;
 if(!installOne(lib,address,add,"?notifyRaceChange@MedicalSystem@@QEAAXPEAVGameData@@@Z",reinterpret_cast<void*>(&onRaceChange),reinterpret_cast<void**>(&originalRace),raceReady))return false;
 if(!installOne(lib,address,add,"?crushLimb@MedicalSystem@@QEAAXW4Limb@RobotLimbs@@@Z",reinterpret_cast<void*>(&onCrush),reinterpret_cast<void**>(&originalCrush),crushReady))return false;
 if(!installOne(lib,address,add,"?amputate@MedicalSystem@@QEAAXW4Limb@RobotLimbs@@_NAEBVVector3@Ogre@@@Z",reinterpret_cast<void*>(&onAmputate),reinterpret_cast<void**>(&originalAmputate),amputateReady))return false;
 hooksReady=true;
 KenshiLua::LogInfo("[KenshiShopNative] NoSever91 hooks ready; medical destructor/race-change cleanup enabled");
 return true;
}
static int fail(lua_State* L,const char* why) {
 KenshiLua::Push(L,false);KenshiLua::Push(L,why);return 2;
}
static int raceNumber(const std::string& id) {
 for(int n=7101;n<=7117;++n) {
  if(n>7106&&n<7110)continue;
  if(id==std::to_string(n)+"-KenshiShop.mod")return n;
 }
 return 0;
}
static int protect(lua_State* L) {
 void* med=KenshiLua::TestObject(L,1,"KenshiLua.MedicalSystem");
 int race=raceNumber(KenshiLua::GetString(L,2));
 if(!med||!race)return fail(L,"NOSEVER_INVALID_MEDICAL_OR_RACE");
 if(!install())return fail(L,"NOSEVER_NATIVE_HOOK_INSTALL_FAILED");
 Protection result;
 try {
  AcquireSRWLockExclusive(&registryLock);
  auto found=registry.find(med);
  if(found==registry.end())found=registry.emplace(med,Protection{race,0,0}).first;
  else if(found->second.race!=race)found->second=Protection{race,0,0};
  result=found->second;
  ReleaseSRWLockExclusive(&registryLock);
 } catch(...) {
  ReleaseSRWLockExclusive(&registryLock);return fail(L,"NOSEVER_REGISTRY_ALLOCATION_FAILED");
 }
 KenshiLua::Push(L,true);KenshiLua::Push(L,static_cast<double>(result.amputations));
 KenshiLua::Push(L,static_cast<double>(result.crushes));return 3;
}
static int unprotect(lua_State* L) {
 void* med=KenshiLua::TestObject(L,1,"KenshiLua.MedicalSystem");
 if(!med)return fail(L,"NOSEVER_INVALID_MEDICAL");
 forget(med);KenshiLua::Push(L,true);return 1;
}
}
