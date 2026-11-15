#include <windows.h>
#include <cstdio>
int main(){
 HMODULE runtime=LoadLibraryA("KenshiLua.dll");
 HMODULE lib=LoadLibraryA("KenshiLib.dll");
 HMODULE bridge=LoadLibraryA("KenshiShopNative.dll");
 if(!runtime||!lib||!bridge){std::printf("LoadLibrary failed: %lu\n",GetLastError());return 10;}
 typedef int(*Run)(HMODULE);Run run=reinterpret_cast<Run>(GetProcAddress(runtime,"runCases"));
 int result=run?run(bridge):11;
 std::printf("Native DLL loading/export/SDK marshalling/factory ABI/invalid-argument probe: %d\n",result);
 return result;
}
