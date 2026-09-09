#pragma once
#include <array>
#include <cstddef>
#include <optional>
#include <string_view>
#include "http_method.hpp"

namespace fiber {

struct Header {
    std::string_view name;
    std::string_view value;
};

struct Request {
    Method method = Method::UNKNOWN;
    std::string_view path;
    int minor_version = 1;
    std::array<Header, 32> headers{};
    size_t num_headers = 0;
    std::string_view body;

    [[nodiscard]] std::optional<std::string_view> header(std::string_view key) const {
        const auto header_count = num_headers < headers.size() ? num_headers : headers.size();
        for (std::size_t i = 0; i < header_count; ++i) {
            const auto name = headers[i].name;
            if (name.size() != key.size()) {
                continue;
            }

            bool matches = true;
            for (std::size_t character = 0; character < key.size(); ++character) {
                const auto name_character = name[character];
                const auto key_character = key[character];
                const auto lowercase = [](char value) {
                    return value >= 'A' && value <= 'Z'
                        ? static_cast<char>(value - 'A' + 'a')
                        : value;
                };

                if (lowercase(name_character) != lowercase(key_character)) {
                    matches = false;
                    break;
                }
            }

            if (matches) {
                return headers[i].value;
            }
        }
        return std::nullopt;
    }
};

} // namespace fiber