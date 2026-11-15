// GPL-3.0: native marshalling for the existing KenshiLib node factory only.
// No hooks, offsets, memory writes, movement orders or AI implementation.
#include "vendor/KenshiLua.h"
#include <cmath>

namespace {
struct Position { float x,y,z; };
struct Rotation { float w,x,y,z; };
static_assert(sizeof(Position)==12 && sizeof(Rotation)==16,"Ogre value ABI");
static_assert(sizeof(KenshiLua_ApiV1)==328,"KenshiLua ABI v1");
// Exact public x64 export in the supplied KenshiLib.dll. The DLL resolves the
// engine address for its supported game version; no game RVA is used here.
const char* factorySymbol = "?createLocationNode@RootObjectFactory@@QEAAPEAVLocationNode@@_NPEAVGameData@@VVector3@Ogre@@PEAVBuilding@@PEAVFaction@@VQuaternion@5@PEAVGameSaveState@@AEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@Z";
typedef void* (__fastcall* FactoryFn)(void*,bool,void*,Position,void*,void*,Rotation,void*,const std::string&);
int failure(lua_State* L,const char* message) {
 KenshiLua::PushNil(L);KenshiLua::Push(L,message);return 2;
}
int create(lua_State* L) {
 void* factory=KenshiLua::TestObject(L,1,"KenshiLua.RootObjectFactory");
 void* data=KenshiLua::TestObject(L,2,"KenshiLua.GameData");
 void* building=KenshiLua::TestObject(L,3,"KenshiLua.Building");
 void* faction=KenshiLua::TestObject(L,4,"KenshiLua.Faction");
 if(!factory||!data||!building||!faction)return failure(L,"NATIVE_NODE_INVALID_OBJECT");
 float v[7];for(int i=0;i<7;++i) {
  if(KenshiLua::Detail::GetApi()->type(L,i+5)!=3)return failure(L,"NATIVE_NODE_NUMBER_REQUIRED");
  double value=KenshiLua::GetNumber(L,i+5);
  if(!std::isfinite(value)||std::abs(value)>1e8)return failure(L,"NATIVE_NODE_INVALID_POSE");
  v[i]=static_cast<float>(value);
 }
 HMODULE module=GetModuleHandleA("KenshiLib.dll");
 FactoryFn fn=module?reinterpret_cast<FactoryFn>(GetProcAddress(module,factorySymbol)):NULL;
 if(!fn)return failure(L,"KENSHILIB_NODE_FACTORY_EXPORT_UNAVAILABLE");
 try {
  // NODE_SHOPKEEPER / NODE_GENERAL / NODE_GUARD_POST share a RootObjectBase
  // prefix (RTTI in the supplied EXE confirms both base offsets are zero).
  // SDK pushObject performs the same non-owning wrapping as the
  // standard RootObjectFactory.create binding. The opaque pointer stays in C++.
  Position p={v[0],v[1],v[2]};Rotation q={v[3],v[4],v[5],v[6]};
  const std::string unusedId;
  void* node=fn(factory,true,data,p,building,faction,q,NULL,unusedId);
  if(!node)return failure(L,"NATIVE_NODE_CREATION_FAILED");
  if(KenshiLua::PushObject(L,node,"KenshiLua.RootObject")!=KenshiLua::STATUS_OK)
   return failure(L,"NATIVE_NODE_MARSHAL_FAILED");
  return 1;
 } catch(...) {return failure(L,"NATIVE_NODE_FACTORY_EXCEPTION");}
}
const KenshiLua::Reg methods[]={{"createNode",create},{NULL,NULL}};
}
extern "C" __declspec(dllexport) int luaopen_KenshiShopNative(lua_State* L) {
 if(!KenshiLua::IsAvailable())return 0;
 KenshiLua::NewTable(L);KenshiLua::RegisterFunctions(L,methods);
 KenshiLua::Push(L,1);KenshiLua::SetField(L,-2,"abi");
 KenshiLua::LogInfo("[KenshiShopNative] node marshalling ready; no AI hooks");
 return 1;
}
