module agent_harness.app;

import std.conv;
import std.stdio;

import asdf;

import agent_harness.client;
import agent_harness.llamacpp_proto;

void main(string[] args) {
    string port = "8080";
    if (args.length > 1) {
        port = args[1];
    }
    auto host = ModelServer("localhost", port);
    auto req = host.makeReq("Who are you?");
    writeln(host.makeChatReq(req));
}
