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

struct ModelServerEndpoint {
    string proto;
    string host;
    string port;
}

class ModelServer {
    ModelServerEndpoint endpoint;
    string model;
    // Used for header based authentication, for openai/gemini endpoints
    string[string] headerOverrides;
    Logger logger;

    this(ModelServerEndpoint endpoint) {
        this.endpoint = endpoint;
    }

    string apiUrl() const => format!"%s://%s:%s/v1/chat/completions"(endpoint.proto, endpoint.host, endpoint.port);

    Logger getLogger() => logger is null ? stdThreadLocalLog : logger;

    // TODO(ccapitalk): Subclass, overrides for the different providers
    bool healthCheck() const {
        auto url = format!"http://%s:%s/props"(endpoint.host, endpoint.port);
        try {
            get(url);
        } catch(CurlException exception) {
            return false;
        }
        return true;
    }

    LlamaResponse sendReq(LlamaMessage[] history, LlamaToolDef[] apiToolDefs=[]) {
        auto payload = LlamaReq(
            model: model,
            messages: history,
            tools: apiToolDefs,
        ).serializeToJson;

        // TODO: Streaming fetch
        auto builder = appender!(ubyte[]);
        // TODO: Handle curl exceptions properly, categorize them
        auto http = HTTP(apiUrl());
        http.method = HTTP.Method.get;

        http.contentLength = payload.length;
        foreach (kv; headerOverrides.byPair) {
            http.addRequestHeader(kv[0], kv[1]);
        }

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
        getLogger().tracef("Received response: %s", str);
        return str.deserialize!LlamaResponse;
    }
}

ModelServerEndpoint httpEndpoint(string host, string port) => ModelServerEndpoint("http", host, port);
ModelServerEndpoint httpsEndpoint(string host, string port) => ModelServerEndpoint("https", host, port);
