#pragma once

#include <coroutine>
#include <exception>
#include <optional>
#include <stdexcept>
#include <type_traits>
#include <utility>

namespace fiber {

template <typename T>
class [[nodiscard]] Task {
    static_assert(!std::is_void_v<T>);

public:
    struct promise_type;
    using handle_type = std::coroutine_handle<promise_type>;

    struct promise_type {
        std::optional<T> value;
        std::exception_ptr error;
        std::coroutine_handle<> continuation;

        Task get_return_object() noexcept { return Task{handle_type::from_promise(*this)}; }
        std::suspend_never initial_suspend() const noexcept { return {}; }
        auto final_suspend() const noexcept {
            struct FinalAwaiter {
                bool await_ready() const noexcept { return false; }
                std::coroutine_handle<> await_suspend(handle_type current) const noexcept {
                    return current.promise().continuation ? current.promise().continuation : std::noop_coroutine();
                }
                void await_resume() const noexcept {}
            };
            return FinalAwaiter{};
        }
        void return_value(T result) noexcept { value.emplace(std::move(result)); }
        void unhandled_exception() noexcept { error = std::current_exception(); }
    };

    Task() noexcept = default;
    Task(Task&& other) noexcept : handle_(std::exchange(other.handle_, {})) {}
    Task& operator=(Task&& other) noexcept {
        if (this != &other) {
            destroy();
            handle_ = std::exchange(other.handle_, {});
        }
        return *this;
    }
    Task(const Task&) = delete;
    Task& operator=(const Task&) = delete;
    ~Task() { destroy(); }

    bool done() const noexcept { return !handle_ || handle_.done(); }

    T result() {
        if (!handle_) {
            throw std::logic_error("result requested from empty Task");
        }
        if (handle_.promise().error) {
            std::rethrow_exception(handle_.promise().error);
        }
        return std::move(*handle_.promise().value);
    }

    struct Awaiter {
        handle_type handle;
        bool await_ready() const noexcept { return !handle || handle.done(); }
        std::coroutine_handle<> await_suspend(std::coroutine_handle<> continuation) const noexcept {
            handle.promise().continuation = continuation;
            return handle;
        }
        T await_resume() { return handle.promise().error ? throw_error() : std::move(*handle.promise().value); }

    private:
        T throw_error() {
            std::rethrow_exception(handle.promise().error);
        }
    };

    Awaiter operator co_await() && noexcept { return {handle_}; }

private:
    explicit Task(handle_type handle) noexcept : handle_(handle) {}
    void destroy() noexcept {
        if (handle_) {
            handle_.destroy();
            handle_ = {};
        }
    }

    handle_type handle_{};
};

template <>
class [[nodiscard]] Task<void> {
public:
    struct promise_type;
    using handle_type = std::coroutine_handle<promise_type>;

    struct promise_type {
        std::exception_ptr error;
        std::coroutine_handle<> continuation;

        Task get_return_object() noexcept { return Task{handle_type::from_promise(*this)}; }
        std::suspend_never initial_suspend() const noexcept { return {}; }
        auto final_suspend() const noexcept {
            struct FinalAwaiter {
                bool await_ready() const noexcept { return false; }
                std::coroutine_handle<> await_suspend(handle_type current) const noexcept {
                    return current.promise().continuation ? current.promise().continuation : std::noop_coroutine();
                }
                void await_resume() const noexcept {}
            };
            return FinalAwaiter{};
        }
        void return_void() const noexcept {}
        void unhandled_exception() noexcept { error = std::current_exception(); }
    };

    Task() noexcept = default;
    Task(Task&& other) noexcept : handle_(std::exchange(other.handle_, {})) {}
    Task& operator=(Task&& other) noexcept {
        if (this != &other) {
            destroy();
            handle_ = std::exchange(other.handle_, {});
        }
        return *this;
    }
    Task(const Task&) = delete;
    Task& operator=(const Task&) = delete;
    ~Task() { destroy(); }

    bool done() const noexcept { return !handle_ || handle_.done(); }
    void result() {
        if (handle_ && handle_.promise().error) {
            std::rethrow_exception(handle_.promise().error);
        }
    }

    struct Awaiter {
        handle_type handle;
        bool await_ready() const noexcept { return !handle || handle.done(); }
        std::coroutine_handle<> await_suspend(std::coroutine_handle<> continuation) const noexcept {
            handle.promise().continuation = continuation;
            return handle;
        }
        void await_resume() const {
            if (handle && handle.promise().error) {
                std::rethrow_exception(handle.promise().error);
            }
        }
    };

    Awaiter operator co_await() && noexcept { return {handle_}; }

private:
    explicit Task(handle_type handle) noexcept : handle_(handle) {}
    void destroy() noexcept {
        if (handle_) {
            handle_.destroy();
            handle_ = {};
        }
    }

    handle_type handle_{};
};

} // namespace fiber
