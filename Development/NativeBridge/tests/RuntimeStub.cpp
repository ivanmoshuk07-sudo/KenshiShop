// Minimal C ABI harness. No Lua engine and no Kenshi AI are emulated.
#define KENSHILUA_BUILDING_DLL
#include "../vendor/KenshiLua.h"
#include <cstdint>
struct lua_State {};
static lua_CFunction createNode=NULL;
static bool marshalled=false;
static int bad=0;
static int initialized(){return 1;}
static void table(lua_State*){}
static void integer(lua_State*,ptrdiff_t){}
static void field(lua_State*,int,const char*){}
static void nil(lua_State*){}
static void string(lua_State*,const char*){}
static void* object(lua_State*,int index,const char*){return bad==2?NULL:reinterpret_cast<void*>(static_cast<uintptr_t>(index*0x1000));}
static int push(lua_State*,void* ptr,const char* meta){marshalled=ptr==reinterpret_cast<void*>(0x5000)&&!std::strcmp(meta,"KenshiLua.RootObject");return marshalled?0:2;}
static double number(lua_State*,int index){const double values[]={1.25,2.5,3.75,1,0,0,0};return values[index-5];}
static int type(lua_State*,int){return bad==1?4:3;}
static void functions(lua_State*,const KenshiLua_Reg* methods){for(;methods->name;++methods)if(!std::strcmp(methods->name,"createNode"))createNode=methods->function;}
extern "C" __declspec(dllexport) int __cdecl KenshiLua_GetApi(unsigned int version,KenshiLua_ApiV1* out,size_t size){
 if(version!=1||size<sizeof(*out))return 7;
 std::memset(out,0,sizeof(*out));out->abiVersion=1;out->structSize=sizeof(*out);
 out->isInitialized=initialized;out->testObject=object;out->pushObject=push;out->newTable=table;
 out->pushInteger=integer;out->setField=field;out->registerFunctions=functions;out->toNumber=number;
 out->type=type;out->pushNil=nil;out->pushString=string;return 0;
}
extern "C" __declspec(dllexport) int runCases(HMODULE bridge){
 typedef int(*Open)(lua_State*);
 Open open=reinterpret_cast<Open>(GetProcAddress(bridge,"luaopen_KenshiShopNative"));
 if(!open)return 1;
 lua_State state;
 if(open(&state)!=1||!createNode)return 2;
 if(createNode(&state)!=1||!marshalled)return 3;
 bad=1;marshalled=false;if(createNode(&state)!=2||marshalled)return 4;
 bad=2;if(createNode(&state)!=2||marshalled)return 5;
 return 0;
}
