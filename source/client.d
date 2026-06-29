module agent_harness.client;

import std.array;
import std.format;
import std.logger;
import std.net.curl;
import std.stdio;

import asdf;

import agent_harness.llamacpp_proto;
import agent_harness.tool;

// TODO: Enforce https if not localhost
string apiUrl(ModelServer host) =>
    format!"http://%s:%s/v1/chat/completions"(host.host, host.port);

struct ModelServer {
    string host;
    string port;
    string model = "qwen3:8b";
    Logger logger;
    ToolSet toolSet;

    Logger getLogger() => logger is null ? stdThreadLocalLog : logger;
}

bool healthCheck(ModelServer server) {
    auto url = format!"http://%s:%s/props"(server.host, server.port);
    try {
        get(url);
    } catch(CurlException exception) {
        return false;
    }
    return true;
}

LlamaResponse sendReq(ModelServer server, LlamaMessage[] history) {
    auto req = LlamaReq(
        model: server.model,
        messages: history,
        tools: server.toolSet.apiToolDefs,
    );
    auto payload = req.serializeToJson;
    // TODO: Streaming fetch
    auto builder = appender!(ubyte[]);
    auto http = HTTP(server.apiUrl());
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
    server.getLogger.tracef("Received response: %s", str);
    return str.deserialize!LlamaResponse;
}
