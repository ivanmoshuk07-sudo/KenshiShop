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
