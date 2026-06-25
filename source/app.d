module agent_harness.app;

import std.array;
import std.conv;
import std.format;
import std.net.curl;
import std.stdio;

import asdf;

import agent_harness.proto;

/*
ollama pull qwen3:8b      # ~5GB, fits your 12GB with lots of headroom
ollama serve              # starts the HTTP server on 127.0.0.1:11434
*/

// TODO: Enforce https if not localhost
string apiUrl(Host host) =>
    format!"http://%s:%s/api/chat"(host.host, host.port);

struct Host {
    string host;
    string port;
}

OllamaResponse makeChatReq(Host host, OllamaReq req) {
    auto payload = req.serializeToJson;
    // TODO: Streaming fetch
    auto builder = appender!(ubyte[]);
    auto http = HTTP(host.apiUrl());
    http.method = HTTP.Method.get;
    http.contentLength = payload.length;
    http.onSend = (void[] data) {
        auto m = cast(void[]) payload;
        size_t len = m.length > data.length ? data.length : m.length;
        if (len == 0) return len;
        data[0 .. len] = m[0 .. len];
        payload = payload[len..$];
        return len;
    };
    http.onReceive = (ubyte[] data) {
        builder.put(data);
        return data.length;
    };
    http.perform();
    auto str = cast(string) builder.data().idup;
    return str.deserialize!OllamaResponse;
}

OllamaReq makeReq(string prompt, OllamaMessage[] history = []) {
    return OllamaReq(
        model: "qwen3:8b",
        messages: history ~ [OllamaMessage(role: "user", content: prompt)]
    );
}

void main(string[] args) {
    string port = "11434";
    if (args.length > 1) {
        port = args[1];
    }
    auto host = Host("localhost", port);
    auto req = makeReq("Who are you?");
    writeln(host.makeChatReq(req));
}
