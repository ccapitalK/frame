module agent_harness.client;

import std.array;
import std.format;
import std.net.curl;
import std.stdio;

import asdf;

import agent_harness.llamacpp_proto;

// TODO: Enforce https if not localhost
string apiUrl(ModelServer host) =>
    format!"http://%s:%s/v1/chat/completions"(host.host, host.port);

struct ModelServer {
    string host;
    string port;
    string model = "qwen3:8b";
    // TODO: Remove this
    bool printResponses = false;
    LlamaToolDef[] tools;
}

LlamaResponse sendReq(ModelServer server, LlamaMessage[] history) {
    auto req = LlamaReq(
        model: server.model,
        messages: history,
        tools: server.tools,
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
    if (server.printResponses) writeln(str);
    return str.deserialize!LlamaResponse;
}

/// Put this at the start of the history to provide a system prompt
LlamaMessage systemPrompt(string prompt) => LlamaMessage(role: "system", content: prompt);

LlamaMessage userPrompt(string prompt) => LlamaMessage(role: "user", content: prompt);

struct ToolDef {
    LlamaToolDef apiToolDef;
    string delegate(string) method;
}

struct ToolSet {
    LlamaToolDef[] apiToolDefs;
    ToolDef[string] tools;
}

ToolSet makeToolSet(ToolDef[] defs) {
    ToolDef[string] tools;
    LlamaToolDef[] apiToolDefs;
    foreach (def; defs) {
        auto name = def.apiToolDef.function_.name;
        tools[name] = def;
        apiToolDefs ~= def.apiToolDef;
    }
    return ToolSet(
        apiToolDefs: apiToolDefs,
        tools: tools,
    );
}

string delegate(string) wrapFuncWithJson(alias f, Req)() {
    return (string v) {
        auto decoded = v.deserialize!Req;
        return f(decoded).serializeToJson;
    };
}

void handleToolResponses(ref LlamaMessage[] history, ToolSet toolSet) {
    auto lastMessage = history[$ - 1];
    if (lastMessage.toolCalls == []) {
        return;
    }
    foreach (call; lastMessage.toolCalls) {
        auto funcName = call.function_.name;
        auto argsJson = call.function_.argumentsJson;
        string resp;
        try {
            auto method = toolSet.tools[funcName].method;
            resp = method(argsJson);
        } catch(Exception e) {
            resp = "Internal error";
        }
        // TODO: Handle errors
        history ~= [
            LlamaMessage(role : "tool", toolCallId: call.id, content: resp)
        ];
    }
}
