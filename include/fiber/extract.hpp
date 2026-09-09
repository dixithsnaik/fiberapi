#pragma once

#include <charconv>
#include <string_view>
#include <type_traits>

namespace fiber {

template <typename T, typename Enable = void>
struct Extractor;

template <typename T>
struct Extractor<T, std::enable_if_t<std::is_integral_v<T>>> {
    static bool parse(std::string_view text, T& value) noexcept {
        const auto* first = text.data();
        const auto* last = first + text.size();
        const auto result = std::from_chars(first, last, value);
        return result.ec == std::errc{} && result.ptr == last;
    }
};

template <>
struct Extractor<std::string_view> {
    static bool parse(std::string_view text, std::string_view& value) noexcept {
        value = text;
        return true;
    }
};

} // namespace fiber
