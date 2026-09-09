#include "fiber/server.hpp"

#include <string>

using fiber::Context;
using fiber::Response;
using fiber::Router;
using fiber::Server;

bool request_id_middleware(Context& ctx) {
    ctx.set_header("X-Request-ID", "fiber-request");
    return true;
}

bool auth_middleware(Context& ctx) {
    const auto authorization = ctx.request().header("Authorization");
    if (!authorization || !authorization->starts_with("Bearer ")) {
        ctx.response() = Response{401, "text/plain; charset=utf-8", "Unauthorized"};
        return false;
    }
    ctx.set("user_id", std::string(authorization->substr(7)));
    return true;
}

int main() {
    Router app;

    app.use(request_id_middleware);
    // app.use(auth_middleware);

    app.get("/ping", [](Context& ctx) {
        ctx.text("pong");
    });

    app.get<int>("/users/:id", [](Context& ctx, int user_id) {
        const auto* identity = ctx.get<std::string>("user_id");
        const std::string identity_text = identity == nullptr ? "unknown" : *identity;
        ctx.json(std::string("{\"id\":") + std::to_string(user_id) +
                     ",\"user\":\"" + identity_text + "\"}");
    });
    app.post("/echo", [](Context& ctx) {
        ctx.status(201);
        ctx.text(ctx.request().body);
    });

    Server server(app, 8080);
    server.run();
}
