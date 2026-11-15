// ABI probe only. Does not contain game code or simulate any AI.
#include <string>
#include <cstdint>
namespace Ogre {class Vector3 {public:float x,y,z;};class Quaternion {public:float w,x,y,z;};}
class GameData;class Building;class Faction;class GameSaveState;class LocationNode;
class RootObjectFactory {public:
 __declspec(dllexport) LocationNode* createLocationNode(bool,GameData*,Ogre::Vector3,Building*,Faction*,Ogre::Quaternion,GameSaveState*,const std::string&);
};
LocationNode* RootObjectFactory::createLocationNode(bool add,GameData* data,Ogre::Vector3 p,Building* b,Faction* f,Ogre::Quaternion q,GameSaveState* save,const std::string& id) {
 if(reinterpret_cast<uintptr_t>(this)!=0x1000 || !add || reinterpret_cast<uintptr_t>(data)!=0x2000
 || reinterpret_cast<uintptr_t>(b)!=0x3000 || reinterpret_cast<uintptr_t>(f)!=0x4000 || save || !id.empty()
 || p.x!=1.25f || p.y!=2.5f || p.z!=3.75f || q.w!=1 || q.x!=0 || q.y!=0 || q.z!=0)return NULL;
 return reinterpret_cast<LocationNode*>(0x5000);
}

// Test public medical ABI and forwarding independently of the bridge policy.
#include <windows.h>
class RobotLimbs {public:enum Limb {L0,L1,L2,L3};};
class MedicalSystem {public:
 __declspec(dllexport) void amputate(RobotLimbs::Limb,bool,const Ogre::Vector3&);
 __declspec(dllexport) void crushLimb(RobotLimbs::Limb);
 __declspec(dllexport) void _DESTRUCTOR();
 __declspec(dllexport) void notifyRaceChange(GameData*);
};
static volatile LONG calls[4]={0,0,0,0};
void MedicalSystem::amputate(RobotLimbs::Limb,bool,const Ogre::Vector3&){InterlockedIncrement(&calls[0]);}
void MedicalSystem::crushLimb(RobotLimbs::Limb){InterlockedIncrement(&calls[1]);}
void MedicalSystem::_DESTRUCTOR(){InterlockedIncrement(&calls[2]);}
void MedicalSystem::notifyRaceChange(GameData*){InterlockedIncrement(&calls[3]);}
struct Hook {void* target;void* detour;};
static Hook installed[8];static int hookCount=0;
namespace KenshiLib {
 enum HookStatus {SUCCESS,FAIL};
 __declspec(dllexport) intptr_t GetRealAddress(void* function){return reinterpret_cast<intptr_t>(function);}
 __declspec(dllexport) HookStatus AddHook(void* target,void* detour,void** original){
  if(hookCount>=8||!target||!detour||!original)return FAIL;
  *original=target;installed[hookCount++]={target,detour};return SUCCESS;
 }
}
extern "C" __declspec(dllexport) int medicalCalls(int kind){return calls[kind];}
extern "C" __declspec(dllexport) void medicalAction(void* med,int kind,int limb){
 const char* symbols[]={
 "?amputate@MedicalSystem@@QEAAXW4Limb@RobotLimbs@@_NAEBVVector3@Ogre@@@Z",
 "?crushLimb@MedicalSystem@@QEAAXW4Limb@RobotLimbs@@@Z",
 "?_DESTRUCTOR@MedicalSystem@@QEAAXXZ",
 "?notifyRaceChange@MedicalSystem@@QEAAXPEAVGameData@@@Z"};
 void* target=reinterpret_cast<void*>(GetProcAddress(GetModuleHandleA("KenshiLib.dll"),symbols[kind]));
 for(int i=0;i<hookCount;++i)if(installed[i].target==target){target=installed[i].detour;break;}
 if(kind==0){typedef void(__fastcall* Fn)(void*,int,bool,const Ogre::Vector3&);Ogre::Vector3 force={1,2,3};reinterpret_cast<Fn>(target)(med,limb,true,force);}
 else if(kind==1){typedef void(__fastcall* Fn)(void*,int);reinterpret_cast<Fn>(target)(med,limb);}
 else if(kind==2){typedef void(__fastcall* Fn)(void*);reinterpret_cast<Fn>(target)(med);}
 else {typedef void(__fastcall* Fn)(void*,void*);reinterpret_cast<Fn>(target)(med,NULL);}
}
