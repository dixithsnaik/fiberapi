#pragma once

#include "request.hpp"
#include "response.hpp"

#include <any>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace fiber {

class Context {
public:
    explicit Context(Request& request) noexcept : request_(request) {}

    Request& request() noexcept { return request_; }
    const Request& request() const noexcept { return request_; }
    Response& response() noexcept { return response_; }
    const Response& response() const noexcept { return response_; }

    void set_header(std::string name, std::string value) {
        for (auto& header : res_headers) {
            if (header.first == name) {
                header.second = std::move(value);
                return;
            }
        }
        res_headers.emplace_back(std::move(name), std::move(value));
    }

    void status(int code) noexcept { response_.status_code = code; }

    void json(std::string_view value) noexcept {
        response_storage_.clear();
        response_.content_type = "application/json; charset=utf-8";
        response_.body = value;
    }

    void json(std::string&& value) {
        response_storage_ = std::move(value);
        response_.content_type = "application/json; charset=utf-8";
        response_.body = response_storage_;
    }

    template <std::size_t size>
    void json(const char (&value)[size]) noexcept {
        json(std::string_view(value, size - 1));
    }

    void text(std::string_view value) noexcept {
        response_storage_.clear();
        response_.content_type = "text/plain; charset=utf-8";
        response_.body = value;
    }

    void text(std::string&& value) {
        response_storage_ = std::move(value);
        response_.content_type = "text/plain; charset=utf-8";
        response_.body = response_storage_;
    }

    template <std::size_t size>
    void text(const char (&value)[size]) noexcept {
        text(std::string_view(value, size - 1));
    }

    void html(std::string_view value) noexcept {
        response_storage_.clear();
        response_.content_type = "text/html; charset=utf-8";
        response_.body = value;
    }

    void html(std::string&& value) {
        response_storage_ = std::move(value);
        response_.content_type = "text/html; charset=utf-8";
        response_.body = response_storage_;
    }

    template <std::size_t size>
    void html(const char (&value)[size]) noexcept {
        html(std::string_view(value, size - 1));
    }

    template <typename T>
    void set(std::string key, T value) {
        locals[std::move(key)] = std::move(value);
    }

    template <typename T>
    T* get(std::string_view key) noexcept {
        const auto found = locals.find(std::string(key));
        if (found == locals.end()) {
            return nullptr;
        }
        return std::any_cast<T>(&found->second);
    }

    template <typename T>
    const T* get(std::string_view key) const noexcept {
        const auto found = locals.find(std::string(key));
        if (found == locals.end()) {
            return nullptr;
        }
        return std::any_cast<T>(&found->second);
    }

    std::string serialize_response() const {
        std::string wire;
        wire.reserve(128 + response_.body.size());
        wire.append("HTTP/1.1 ");
        wire.append(status_reason(response_.status_code));
        wire.append("\r\nContent-Type: ");
        wire.append(response_.content_type);
        wire.append("\r\nContent-Length: ");
        wire.append(std::to_string(response_.body.size()));
        wire.append("\r\nConnection: close\r\n");
        for (const auto& [name, value] : res_headers) {
            wire.append(name);
            wire.append(": ");
            wire.append(value);
            wire.append("\r\n");
        }
        wire.append("\r\n");
        wire.append(response_.body);
        return wire;
    }

    std::vector<std::pair<std::string, std::string>> res_headers;
    std::unordered_map<std::string, std::any> locals;

private:
    static std::string_view status_reason(int code) noexcept {
        switch (code) {
            case 200: return "200 OK";
            case 201: return "201 Created";
            case 204: return "204 No Content";
            case 400: return "400 Bad Request";
            case 401: return "401 Unauthorized";
            case 404: return "404 Not Found";
            case 405: return "405 Method Not Allowed";
            case 500: return "500 Internal Server Error";
            default: return "500 Internal Server Error";
        }
    }

    Request& request_;
    Response response_{};
    std::string response_storage_;
};

} // namespace fiber
