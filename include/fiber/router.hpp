#pragma once

#include "context.hpp"
#include "extract.hpp"
#include "task.hpp"

#include <functional>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

namespace fiber {

class Router {
public:
    using Middleware = std::function<Task<bool>(Context&)>;

    template <typename Handler>
    void use(Handler&& middleware) {
        middlewares_.emplace_back([callable = std::forward<Handler>(middleware)](Context& context) mutable -> Task<bool> {
            using Result = std::invoke_result_t<decltype(callable)&, Context&>;
            if constexpr (std::is_same_v<Result, Task<bool>>) {
                co_return co_await callable(context);
            } else if constexpr (std::is_same_v<Result, bool>) {
                co_return callable(context);
            } else {
                callable(context);
                co_return true;
            }
        });
    }

    template <typename Handler>
    void get(std::string_view path, Handler&& handler) {
        add_simple(Method::GET, path, std::forward<Handler>(handler));
    }

    template <typename Handler>
    void post(std::string_view path, Handler&& handler) {
        add_simple(Method::POST, path, std::forward<Handler>(handler));
    }

    template <typename Handler>
    void put(std::string_view path, Handler&& handler) {
        add_simple(Method::PUT, path, std::forward<Handler>(handler));
    }

    template <typename Handler>
    void del(std::string_view path, Handler&& handler) {
        add_simple(Method::DELETE, path, std::forward<Handler>(handler));
    }

    template <typename T, typename Handler>
    void get(std::string_view path, Handler&& handler) {
        static_assert(std::is_integral_v<T> || std::is_same_v<T, std::string_view>);
        Route route;
        route.method = Method::GET;
        route.path = path;
        route.parameter = parameter_name(path);
        route.invoke = [callable = std::forward<Handler>(handler)](Context& context,
                                                                    std::string_view value) mutable -> Task<void> {
            T parameter{};
            if (!Extractor<T>::parse(value, parameter)) {
                context.response() = Response::bad_request();
                co_return;
            }
            co_await invoke_handler(callable, context, parameter);
        };
        routes_.push_back(std::move(route));
    }

    Task<void> handle(Context& context) {
        for (auto& middleware : middlewares_) {
            if (!co_await middleware(context)) {
                co_return;
            }
        }

        bool path_found = false;
        for (auto& route : routes_) {
            std::string_view parameter;
            if (!match(route.path, context.request().path, parameter)) {
                continue;
            }
            path_found = true;
            if (route.method != context.request().method) {
                continue;
            }
            co_await route.invoke(context, parameter);
            co_return;
        }

        context.response() = path_found ? Response::method_not_allowed() : Response::not_found();
    }

private:
    struct Route {
        Method method = Method::UNKNOWN;
        std::string_view path;
        std::string_view parameter;
        std::function<Task<void>(Context&, std::string_view)> invoke;
    };

    template <typename Handler>
    void add_simple(Method method, std::string_view path, Handler&& handler) {
        Route route;
        route.method = method;
        route.path = path;
        route.invoke = [callable = std::forward<Handler>(handler)](Context& context,
                                                                    std::string_view) mutable -> Task<void> {
            co_await invoke_handler(callable, context);
        };
        routes_.push_back(std::move(route));
    }

    template <typename Handler, typename... Arguments>
    static Task<void> invoke_handler(Handler& callable, Context& context, Arguments&&... arguments) {
        using Result = std::invoke_result_t<Handler&, Context&, Arguments...>;
        if constexpr (std::is_same_v<Result, Task<void>>) {
            co_await callable(context, std::forward<Arguments>(arguments)...);
        } else if constexpr (std::is_same_v<Result, Response>) {
            context.response() = callable(context, std::forward<Arguments>(arguments)...);
        } else {
            callable(context, std::forward<Arguments>(arguments)...);
        }
        co_return;
    }

    static std::string_view parameter_name(std::string_view path) noexcept {
        const auto colon = path.find(':');
        return colon == std::string_view::npos ? std::string_view{} : path.substr(colon + 1);
    }

    static bool match(std::string_view pattern, std::string_view path,
                      std::string_view& parameter) noexcept {
        parameter = {};
        const auto colon = pattern.find(':');
        if (colon == std::string_view::npos) {
            return pattern == path;
        }
        const auto prefix = pattern.substr(0, colon);
        if (!path.starts_with(prefix)) {
            return false;
        }
        parameter = path.substr(prefix.size());
        return !parameter.empty() && parameter.find('/') == std::string_view::npos;
    }

    std::vector<Middleware> middlewares_;
    std::vector<Route> routes_;
};

} // namespace fiber
