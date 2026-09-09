#include <fiber/router.hpp>
#include <fiber/server.hpp>

#include <string>

using namespace fiber;

int main() {
    Router app;

    app.get("/health", [](Context& ctx) {
        ctx.json(R"({"ok":true})");
    });

    app.post("/notes", [](Context& ctx) {
        ctx.status(201);
        ctx.json(std::string(R"({"saved":true,"body":")") +
                 std::string(ctx.request().body) + R"("})");
    });

    Server server(app, 8080);
    server.run();
}
