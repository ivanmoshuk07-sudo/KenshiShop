// Minimal C ABI harness. No Lua engine and no Kenshi AI are emulated.
#define KENSHILUA_BUILDING_DLL
#include "../vendor/KenshiLua.h"
#include <cstdint>
struct lua_State {};
static lua_CFunction createNode=NULL,protectLimbs=NULL,unprotectLimbs=NULL;
static std::string raceId="7117-KenshiShop.mod";
static bool lastBoolean=false;
static void boolean(lua_State*,int value){lastBoolean=value!=0;}
static const char* text(lua_State*,int,size_t* length){*length=raceId.size();return raceId.c_str();}
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
static void functions(lua_State*,const KenshiLua_Reg* methods){for(;methods->name;++methods){
 if(!std::strcmp(methods->name,"createNode"))createNode=methods->function;
 if(!std::strcmp(methods->name,"protectLimbs"))protectLimbs=methods->function;
 if(!std::strcmp(methods->name,"unprotectLimbs"))unprotectLimbs=methods->function;
}}
extern "C" __declspec(dllexport) int __cdecl KenshiLua_GetApi(unsigned int version,KenshiLua_ApiV1* out,size_t size){
 if(version!=1||size<sizeof(*out))return 7;
 std::memset(out,0,sizeof(*out));out->abiVersion=1;out->structSize=sizeof(*out);
 out->isInitialized=initialized;out->testObject=object;out->pushObject=push;out->newTable=table;
 out->pushInteger=integer;out->setField=field;out->registerFunctions=functions;out->toNumber=number;
 out->pushBoolean=boolean;out->toLString=text;out->pushNumber=[](lua_State*,double){};out->type=type;out->pushNil=nil;out->pushString=string;return 0;
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
 bad=0;
 if(!protectLimbs||!unprotectLimbs)return 6;
 HMODULE lib=GetModuleHandleA("KenshiLib.dll");
 typedef void(*Action)(void*,int,int);typedef int(*Calls)(int);
 auto action=reinterpret_cast<Action>(GetProcAddress(lib,"medicalAction"));
 auto calls=reinterpret_cast<Calls>(GetProcAddress(lib,"medicalCalls"));
 if(!action||!calls)return 7;
 void* med=reinterpret_cast<void*>(0x1000);void* other=reinterpret_cast<void*>(0x9000);
 raceId="17946-stick_people.mod";if(protectLimbs(&state)!=2||lastBoolean)return 8;
 raceId="7117-KenshiShop.mod";if(protectLimbs(&state)!=3||!lastBoolean)return 9;
 for(int limb=0;limb<4;++limb){action(med,0,limb);action(med,1,limb);}
 if(calls(0)||calls(1))return 10;
 action(other,0,0);action(other,1,1);if(calls(0)!=1||calls(1)!=1)return 11;
 // Native destruction removes registry entries before a medical address is reused.
 action(med,2,0);action(med,0,0);if(calls(2)!=1||calls(0)!=2)return 12;
 if(protectLimbs(&state)!=3||!lastBoolean)return 13;
 // Native race changes remove protection immediately, preserving the original action.
 action(med,3,0);action(med,1,0);if(calls(3)!=1||calls(1)!=2)return 14;
 if(protectLimbs(&state)!=3||!lastBoolean)return 15;
 if(unprotectLimbs(&state)!=1||!lastBoolean)return 16;
 action(med,0,0);if(calls(0)!=3)return 17;
 return 0;
}
