// Declarations of the Windhawk API used by the mod, to check that it compiles
// as Windhawk compiles it (clang, C++23) without Windhawk installed.
#pragma once
#include <windows.h>

#define WH_MOD_ID L"tile-windows"
#define WH_MOD_VERSION L"1.0"
#define Wh_Log(message, ...) Wh_Log_External(message, ##__VA_ARGS__)

void Wh_Log_External(PCWSTR format, ...);
int Wh_GetIntSetting(PCWSTR valueName, ...);
PCWSTR Wh_GetStringSetting(PCWSTR valueName, ...);
void Wh_FreeStringSetting(PCWSTR string);
BOOL Wh_SetFunctionHook(void* targetFunction,
                        void* hookFunction,
                        void** originalFunction);
