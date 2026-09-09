#pragma once

#include <string_view>

namespace fiber {

struct Response {
    int status_code = 200;
    std::string_view content_type = "text/plain; charset=utf-8";
    std::string_view body;

    static constexpr Response ok(std::string_view value = {}) noexcept {
        return {200, "text/plain; charset=utf-8", value};
    }

    static constexpr Response created(std::string_view value = {}) noexcept {
        return {201, "text/plain; charset=utf-8", value};
    }

    static constexpr Response no_content() noexcept {
        return {204, "text/plain; charset=utf-8", {}};
    }

    static constexpr Response json(std::string_view value) noexcept {
        return {200, "application/json; charset=utf-8", value};
    }

    static constexpr Response not_found(std::string_view value = "Not Found") noexcept {
        return {404, "text/plain; charset=utf-8", value};
    }

    static constexpr Response method_not_allowed(std::string_view value = "Method Not Allowed") noexcept {
        return {405, "text/plain; charset=utf-8", value};
    }

    static constexpr Response bad_request(std::string_view value = "Bad Request") noexcept {
        return {400, "text/plain; charset=utf-8", value};
    }
};

} // namespace fiber
