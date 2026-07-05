module frame.client;

import std.array;
import std.conv;
import std.format;
import std.logger;
import std.net.curl;
import std.stdio;

import asdf;

import frame.llamacpp_proto;
import frame.tool;

// TODO: Enforce https if not localhost

struct ModelServerEndpoint {
    string proto;
    string host;
    string port;

    this(string proto, string host, ushort port) {
        this.proto = proto;
        this.host = host;
        this.port = port.to!string;
    }
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

    // TODO(ccapitalk): This is llamacpp-server specific, move into subclass
    protected string apiUrl() const =>
        format!"%s://%s:%s/v1/chat/completions"(endpoint.proto, endpoint.host, endpoint.port);

    Logger getLogger() => logger is null ? stdThreadLocalLog : logger;

    // TODO(ccapitalk): Subclass, overrides for the different providers
    bool healthCheck() const {
        auto url = format!"%s://%s:%s/props"(endpoint.proto, endpoint.host, endpoint.port);
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
        http.method = HTTP.Method.post;

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

class GeminiModelServer: ModelServer {
    string apiKey;
    this(string apiKey) {
        super(httpsEndpoint("generativelanguage.googleapis.com", 443));
        this.apiKey = apiKey;
        headerOverrides["Authorization"] = "Bearer " ~ apiKey;
        headerOverrides["Content-Type"] = "application/json";
    }

    override string apiUrl() const => "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";

    override bool healthCheck() const {
        auto http = HTTP("https://generativelanguage.googleapis.com/v1beta/models");
        http.method = HTTP.Method.get;

        // This endpoint has a different auth header than the openai compatible api
        http.addRequestHeader("x-goog-api-key", apiKey);
        // Null sink for data, to not echo
        http.onReceive = (ubyte[] data) => data.length;

        try {
            http.perform();
            return http.statusLine.code == 200;
        } catch(Exception e) {
            return false;
        }
    }
}

ModelServerEndpoint httpEndpoint(string host, ushort port) => ModelServerEndpoint("http", host, port);
ModelServerEndpoint httpsEndpoint(string host, ushort port) => ModelServerEndpoint("https", host, port);
