#include "fiber/request.hpp"

#include <cassert>

int main() {
    fiber::Request request;
    request.headers[0] = {"Content-Type", "text/plain"};
    request.num_headers = 999;

    assert(request.header("content-type").value() == "text/plain");
    assert(!request.header("content").has_value());
    assert(!request.header("content-type-extra").has_value());
}
