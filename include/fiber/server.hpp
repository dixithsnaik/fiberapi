#pragma once

#ifdef _WIN32

#include "server_windows.hpp"

#else

#include "context.hpp"
#include "router.hpp"
#include "picohttpparser.h"

#include <arpa/inet.h>
#include <array>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <cstring>
#include <cstdint>
#include <fcntl.h>
#include <liburing.h>
#include <memory>
#include <netinet/in.h>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/socket.h>
#include <pthread.h>
#include <sched.h>
#include <thread>
#include <unistd.h>

namespace fiber {

class Server {
public:
    explicit Server(Router& router, uint16_t port = 8080) noexcept
        : router_(router), port_(port) {}

    Server(const Server&) = delete;
    Server& operator=(const Server&) = delete;

    [[noreturn]] void run(unsigned workers = std::thread::hardware_concurrency()) {
        if (workers == 0) {
            workers = 1;
        }
        for (unsigned index = 0; index < workers; ++index) {
            std::thread([this, index] { worker_loop(index); }).detach();
        }
        for (;;) {
            std::this_thread::sleep_for(std::chrono::hours(24));
        }
    }

private:
    static constexpr std::size_t buffer_size = 64 * 1024;
    static constexpr std::size_t max_connections = 256;
    static constexpr std::uint64_t accept_tag = 0;
    static constexpr std::uint64_t receive_tag = 1;
    static constexpr std::uint64_t send_tag = 2;

    struct Connection {
        int fd = -1;
        bool active = false;
        std::size_t used = 0;
        std::size_t sent = 0;
        std::array<char, buffer_size> input{};
        std::string output;
    };

    static std::uint64_t tag(std::uint64_t operation, std::uint64_t index) noexcept {
        return (index << 2) | operation;
    }

    static std::uint64_t operation(std::uint64_t value) noexcept { return value & 3; }
    static std::size_t index(std::uint64_t value) noexcept { return value >> 2; }

    static void close_connection(Connection& connection) noexcept {
        if (connection.fd >= 0) {
            ::close(connection.fd);
        }
        connection = Connection{};
    }

    int create_listener() const {
        const int fd = ::socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
        if (fd < 0) {
            throw std::runtime_error(std::strerror(errno));
        }
        int enabled = 1;
        if (::setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &enabled, sizeof(enabled)) < 0) {
            ::close(fd);
            throw std::runtime_error(std::strerror(errno));
        }
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_port = htons(port_);
        address.sin_addr.s_addr = htonl(INADDR_ANY);
        if (::bind(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) < 0 ||
            ::listen(fd, 4096) < 0) {
            const auto message = std::strerror(errno);
            ::close(fd);
            throw std::runtime_error(message);
        }
        return fd;
    }

    static void submit_accept(io_uring& ring, int listener, sockaddr_in& address,
                              socklen_t& address_length) {
        io_uring_sqe* sqe = io_uring_get_sqe(&ring);
        if (sqe == nullptr) {
            throw std::runtime_error("io_uring submission queue exhausted");
        }
        io_uring_prep_accept(sqe, listener, reinterpret_cast<sockaddr*>(&address),
                             &address_length, SOCK_NONBLOCK | SOCK_CLOEXEC);
        io_uring_sqe_set_data64(sqe, accept_tag);
        if (io_uring_submit(&ring) < 0) {
            throw std::runtime_error("io_uring accept submission failed");
        }
    }

    static void submit_receive(io_uring& ring, Connection& connection, std::size_t slot) {
        io_uring_sqe* sqe = io_uring_get_sqe(&ring);
        if (sqe == nullptr) {
            close_connection(connection);
            return;
        }
        io_uring_prep_recv(sqe, connection.fd, connection.input.data() + connection.used,
                           connection.input.size() - connection.used, 0);
        io_uring_sqe_set_data64(sqe, tag(receive_tag, slot));
        io_uring_submit(&ring);
    }

    static void submit_send(io_uring& ring, Connection& connection, std::size_t slot) {
        io_uring_sqe* sqe = io_uring_get_sqe(&ring);
        if (sqe == nullptr) {
            close_connection(connection);
            return;
        }
        io_uring_prep_send(sqe, connection.fd, connection.output.data() + connection.sent,
                           connection.output.size() - connection.sent, MSG_NOSIGNAL);
        io_uring_sqe_set_data64(sqe, tag(send_tag, slot));
        io_uring_submit(&ring);
    }

    static bool parse_request(Connection& connection, Request& request) {
        const char* method = nullptr;
        const char* path = nullptr;
        std::size_t method_length = 0;
        std::size_t path_length = 0;
        int minor_version = 1;
        std::array<phr_header, 32> headers{};
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
        request.body = {connection.input.data() + parsed, connection.used - static_cast<std::size_t>(parsed)};
        if (const auto content_length = request.header("Content-Length")) {
            std::size_t expected = 0;
            const auto result = std::from_chars(content_length->data(),
                                                content_length->data() + content_length->size(), expected);
            if (result.ec != std::errc{} || result.ptr != content_length->data() + content_length->size() ||
                expected > connection.input.size() - static_cast<std::size_t>(parsed)) {
                return false;
            }
            if (request.body.size() < expected) {
                return false;
            }
            request.body = request.body.substr(0, expected);
        }
        return true;
    }

    void worker_loop(unsigned worker_index) {
        cpu_set_t affinity;
        CPU_ZERO(&affinity);
        const auto cpu_count = std::thread::hardware_concurrency();
        CPU_SET(cpu_count == 0 ? 0 : worker_index % cpu_count, &affinity);
        (void)::pthread_setaffinity_np(::pthread_self(), sizeof(affinity), &affinity);

        io_uring ring{};
        if (io_uring_queue_init(1024, &ring, 0) < 0) {
            return;
        }
        const int listener = create_listener();
        auto connections = std::make_unique<std::array<Connection, max_connections>>();
        sockaddr_in address{};
        socklen_t address_length = sizeof(address);
        submit_accept(ring, listener, address, address_length);

        for (;;) {
            io_uring_cqe* cqe = nullptr;
            if (io_uring_wait_cqe(&ring, &cqe) < 0) {
                continue;
            }
            const auto user_data = io_uring_cqe_get_data64(cqe);
            const int result = cqe->res;
            io_uring_cqe_seen(&ring, cqe);

            if (operation(user_data) == accept_tag) {
                address_length = sizeof(address);
                submit_accept(ring, listener, address, address_length);
                if (result < 0) {
                    continue;
                }
                std::size_t slot = 0;
                while (slot < connections->size() && (*connections)[slot].active) {
                    ++slot;
                }
                if (slot == connections->size()) {
                    ::close(result);
                    continue;
                }
                auto& connection = (*connections)[slot];
                connection.fd = result;
                connection.active = true;
                connection.used = 0;
                connection.sent = 0;
                connection.output.clear();
                submit_receive(ring, connection, slot);
                continue;
            }

            const auto slot = index(user_data);
            if (slot >= connections->size() || !(*connections)[slot].active) {
                continue;
            }
            auto& connection = (*connections)[slot];
            if (result <= 0) {
                close_connection(connection);
                continue;
            }

            if (operation(user_data) == receive_tag) {
                connection.used += static_cast<std::size_t>(result);
                Request request;
                if (parse_request(connection, request)) {
                    Context context(request);
                    auto task = router_.handle(context);
                    task.result();
                    connection.output = context.serialize_response();
                    connection.sent = 0;
                    submit_send(ring, connection, slot);
                } else if (connection.used == connection.input.size()) {
                    Request bad_request;
                    Context context(bad_request);
                    context.response() = Response::bad_request();
                    connection.output = context.serialize_response();
                    connection.sent = 0;
                    submit_send(ring, connection, slot);
                } else {
                    submit_receive(ring, connection, slot);
                }
            } else if (operation(user_data) == send_tag) {
                connection.sent += static_cast<std::size_t>(result);
                if (connection.sent < connection.output.size()) {
                    submit_send(ring, connection, slot);
                } else {
                    close_connection(connection);
                }
            }
        }
    }

    Router& router_;
    uint16_t port_;
};

} // namespace fiber

#endif
