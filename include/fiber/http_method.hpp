#pragma once
#include <cstdint>
#include <string_view>

namespace fiber {

enum class Method : uint8_t {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
    UNKNOWN
};

constexpr Method string_to_method(std::string_view sv) noexcept {
    if (sv == "GET")     return Method::GET;
    if (sv == "POST")    return Method::POST;
    if (sv == "PUT")     return Method::PUT;
    if (sv == "DELETE")  return Method::DELETE;
    if (sv == "PATCH")   return Method::PATCH;
    if (sv == "HEAD")    return Method::HEAD;
    if (sv == "OPTIONS") return Method::OPTIONS;
    return Method::UNKNOWN;
}

constexpr std::string_view method_to_string(Method m) noexcept {
    switch (m) {
        case Method::GET:     return "GET";
        case Method::POST:    return "POST";
        case Method::PUT:     return "PUT";
        case Method::DELETE:  return "DELETE";
        case Method::PATCH:   return "PATCH";
        case Method::HEAD:    return "HEAD";
        case Method::OPTIONS: return "OPTIONS";
        default:              return "UNKNOWN";
    }
}

} // namespace fiber