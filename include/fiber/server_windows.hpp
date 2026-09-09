#pragma once

#include "context.hpp"
#include "router.hpp"
#include "picohttpparser.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <mswsock.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <array>
#include <charconv>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "mswsock.lib")

namespace fiber {

class Server {
public:
    explicit Server(Router& router, std::uint16_t port = 8080) noexcept
        : router_(router), port_(port) {}

    Server(const Server&) = delete;
    Server& operator=(const Server&) = delete;

    [[noreturn]] void run(unsigned workers = std::thread::hardware_concurrency()) {
        if (workers == 0) {
            workers = 1;
        }
        initialize();
        post_accept();

        std::vector<std::thread> threads;
        threads.reserve(workers);
        for (unsigned index = 0; index < workers; ++index) {
            threads.emplace_back([this] { worker_loop(); });
        }
        for (auto& thread : threads) {
            thread.join();
        }
        std::terminate();
    }

private:
    static constexpr std::size_t buffer_size = 64 * 1024;
    static constexpr std::size_t max_headers = 32;

    enum class Operation : std::uint8_t { accept, receive, send };

    struct Connection {
        OVERLAPPED overlapped{};
        SOCKET socket = INVALID_SOCKET;
        Operation operation = Operation::receive;
        std::size_t used = 0;
        std::size_t sent = 0;
        std::array<char, buffer_size> input{};
        std::string output;
        WSABUF buffer{};
    };

    struct AcceptOperation {
        OVERLAPPED overlapped{};
        SOCKET socket = INVALID_SOCKET;
        std::array<char, 2 * (sizeof(sockaddr_in) + 16)> addresses{};
    };

    using AcceptExFunction = BOOL(PASCAL*)(SOCKET, SOCKET, PVOID, DWORD, DWORD, DWORD,
                                           LPDWORD, LPOVERLAPPED);

    static bool parse_request(Connection& connection, Request& request) {
        const char* method = nullptr;
        const char* path = nullptr;
        std::size_t method_length = 0;
        std::size_t path_length = 0;
        int minor_version = 1;
        std::array<phr_header, max_headers> headers{};
        std::size_t header_count = headers.size();
        const int parsed = phr_parse_request(connection.input.data(), connection.used,
                                              &method, &method_length, &path, &path_length,
                                              &minor_version, headers.data(), &header_count, 0);
        if (parsed <= 0) {
            return false;
        }

        request.method = string_to_method({method, method_length});
        request.path = {path, path_length};
        request.minor_version = minor_version;
        request.num_headers = header_count;
        for (std::size_t index = 0; index < header_count; ++index) {
            request.headers[index] = {{headers[index].name, headers[index].name_len},
                                      {headers[index].value, headers[index].value_len}};
        }
        const auto header_end = static_cast<std::size_t>(parsed);
        request.body = {connection.input.data() + header_end, connection.used - header_end};
        if (const auto content_length = request.header("Content-Length")) {
            std::size_t expected = 0;
            const auto result = std::from_chars(content_length->data(),
                                                content_length->data() + content_length->size(), expected);
            if (result.ec != std::errc{} || result.ptr != content_length->data() + content_length->size() ||
                expected > connection.input.size() - header_end || request.body.size() < expected) {
                return false;
            }
            request.body = request.body.substr(0, expected);
        }
        return true;
    }

    static void throw_socket_error(const char* operation) {
        throw std::runtime_error(std::string(operation) + ": WSA error " +
                                 std::to_string(WSAGetLastError()));
    }

    void initialize() {
        WSADATA data{};
        if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
            throw_socket_error("WSAStartup");
        }

        listener_ = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, nullptr, 0,
                               WSA_FLAG_OVERLAPPED);
        if (listener_ == INVALID_SOCKET) {
            throw_socket_error("WSASocket");
        }
        BOOL enabled = TRUE;
        setsockopt(listener_, SOL_SOCKET, SO_REUSEADDR,
                   reinterpret_cast<const char*>(&enabled), sizeof(enabled));

        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_port = htons(port_);
        address.sin_addr.s_addr = htonl(INADDR_ANY);
        if (bind(listener_, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) == SOCKET_ERROR ||
            listen(listener_, SOMAXCONN) == SOCKET_ERROR) {
            throw_socket_error("bind/listen");
        }

        iocp_ = CreateIoCompletionPort(reinterpret_cast<HANDLE>(listener_), nullptr, 0, 0);
        if (iocp_ == nullptr) {
            throw_socket_error("CreateIoCompletionPort");
        }

        GUID accept_ex_guid = WSAID_ACCEPTEX;
        DWORD bytes = 0;
        if (WSAIoctl(listener_, SIO_GET_EXTENSION_FUNCTION_POINTER,
                     &accept_ex_guid, sizeof(accept_ex_guid), &accept_ex_,
                     sizeof(accept_ex_), &bytes, nullptr, nullptr) == SOCKET_ERROR) {
            throw_socket_error("WSAIoctl(AcceptEx)");
        }
    }

    void post_accept() {
        auto operation = std::make_unique<AcceptOperation>();
        operation->socket = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, nullptr, 0,
                                       WSA_FLAG_OVERLAPPED);
        if (operation->socket == INVALID_SOCKET) {
            throw_socket_error("WSASocket(AcceptEx)");
        }
        const BOOL pending = accept_ex_(listener_, operation->socket,
                                        operation->addresses.data(), 0,
                                        sizeof(sockaddr_in) + 16, sizeof(sockaddr_in) + 16,
                                        nullptr, &operation->overlapped);
        if (!pending && WSAGetLastError() != WSA_IO_PENDING) {
            closesocket(operation->socket);
            throw_socket_error("AcceptEx");
        }
        operation.release();
    }

    bool post_receive(Connection& connection) {
        connection.operation = Operation::receive;
        connection.buffer.buf = connection.input.data() + connection.used;
        connection.buffer.len = static_cast<ULONG>(connection.input.size() - connection.used);
        DWORD flags = 0;
        const int result = WSARecv(connection.socket, &connection.buffer, 1, nullptr, &flags,
                                   &connection.overlapped, nullptr);
        if (result == SOCKET_ERROR && WSAGetLastError() != WSA_IO_PENDING) {
            return false;
        }
        return true;
    }

    bool post_send(Connection& connection) {
        connection.operation = Operation::send;
        connection.buffer.buf = connection.output.data() + connection.sent;
        connection.buffer.len = static_cast<ULONG>(connection.output.size() - connection.sent);
        const int result = WSASend(connection.socket, &connection.buffer, 1, nullptr, 0,
                                   &connection.overlapped, nullptr);
        if (result == SOCKET_ERROR && WSAGetLastError() != WSA_IO_PENDING) {
            return false;
        }
        return true;
    }

    static void close_connection(Connection* connection) noexcept {
        if (connection == nullptr) {
            return;
        }
        closesocket(connection->socket);
        delete connection;
    }

    void handle_accept(AcceptOperation* operation, DWORD bytes, BOOL success) {
        (void)bytes;
        if (!success) {
            closesocket(operation->socket);
            delete operation;
            post_accept();
            return;
        }
        setsockopt(operation->socket, SOL_SOCKET, SO_UPDATE_ACCEPT_CONTEXT,
                   reinterpret_cast<const char*>(&listener_), sizeof(listener_));
        auto connection = std::make_unique<Connection>();
        connection->socket = operation->socket;
        if (CreateIoCompletionPort(reinterpret_cast<HANDLE>(connection->socket), iocp_,
                                   reinterpret_cast<ULONG_PTR>(connection.get()), 0) == nullptr) {
            closesocket(connection->socket);
            delete operation;
            throw_socket_error("CreateIoCompletionPort(connection)");
        }
        if (!post_receive(*connection)) {
            closesocket(connection->socket);
            delete operation;
            post_accept();
            return;
        }
        connection.release();
        delete operation;
        post_accept();
    }

    void handle_connection(Connection* connection, DWORD bytes, BOOL success) {
        if (!success || bytes == 0) {
            close_connection(connection);
            return;
        }
        if (connection->operation == Operation::receive) {
            connection->used += bytes;
            Request request;
            if (parse_request(*connection, request)) {
                std::printf("%s %.*s\n", method_to_string(request.method).data(),
                            static_cast<int>(request.path.size()), request.path.data());
                std::fflush(stdout);
                Context context(request);
                auto task = router_.handle(context);
                task.result();
                connection->output = context.serialize_response();
                connection->sent = 0;
                if (!post_send(*connection)) {
                    close_connection(connection);
                }
            } else if (connection->used == connection->input.size()) {
                Request bad_request;
                Context context(bad_request);
                context.response() = Response::bad_request();
                connection->output = context.serialize_response();
                connection->sent = 0;
                if (!post_send(*connection)) {
                    close_connection(connection);
                }
            } else {
                if (!post_receive(*connection)) {
                    close_connection(connection);
                }
            }
            return;
        }

        connection->sent += bytes;
        if (connection->sent < connection->output.size()) {
            if (!post_send(*connection)) {
                close_connection(connection);
            }
        } else {
            close_connection(connection);
        }
    }

    void worker_loop() {
        for (;;) {
            DWORD bytes = 0;
            ULONG_PTR key = 0;
            OVERLAPPED* overlapped = nullptr;
            const BOOL success = GetQueuedCompletionStatus(iocp_, &bytes, &key, &overlapped, INFINITE);
            if (overlapped == nullptr) {
                continue;
            }
            if (key == 0) {
                handle_accept(reinterpret_cast<AcceptOperation*>(overlapped), bytes, success);
            } else {
                handle_connection(reinterpret_cast<Connection*>(key), bytes, success);
            }
        }
    }

    Router& router_;
    std::uint16_t port_;
    SOCKET listener_ = INVALID_SOCKET;
    HANDLE iocp_ = nullptr;
    AcceptExFunction accept_ex_ = nullptr;
};

} // namespace fiber
