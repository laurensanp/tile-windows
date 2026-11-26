// The part of Windhawk's windhawk_utils.h the mod uses, for the test harness
// and the compile check (Windhawk ships the real one with its compiler).
#pragma once
#include <windows.h>

namespace WindhawkUtils {

class StringSetting {
   public:
    StringSetting() = default;
    explicit StringSetting(PCWSTR value) : m_value(value) {}
    StringSetting(StringSetting&& other) noexcept : m_value(other.m_value) {
        other.m_value = nullptr;
    }
    StringSetting(const StringSetting&) = delete;
    StringSetting& operator=(const StringSetting&) = delete;
    ~StringSetting() {
        if (m_value) {
            Wh_FreeStringSetting(m_value);
        }
    }

    template <typename... Args>
    static StringSetting make(PCWSTR valueName, Args... args) {
        return StringSetting(Wh_GetStringSetting(valueName, args...));
    }

    PCWSTR get() const { return m_value; }
    operator PCWSTR() const { return m_value; }

   private:
    PCWSTR m_value = nullptr;
};

}  // namespace WindhawkUtils
