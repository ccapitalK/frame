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

class SessionException : Exception {
    this(string message) {
        super(message);
    }
}

// TODO: Enforce https if not localhost

enum OPENAI_API_PATH = "/v1/chat/completions";

struct ModelServerEndpoint {
    string proto;
    string host;
    string port;
    string path;

    this(string proto, string host, ushort port, string path = OPENAI_API_PATH) {
        this.proto = proto;
        this.host = host;
        this.port = port.to!string;
        if (path.length && path[0] == '/') {
            path = path[1 .. $];
        }
        this.path = path;
    }

    string apiUrl() const => format!"%s://%s:%s/%s"(proto, host, port, path);
}

class ModelServer {
    ModelServerEndpoint endpoint;
    string model;
    string reasoningEffort;
    // Used for header based authentication, for openai/gemini endpoints
    string[string] headerOverrides;
    Logger logger;

    this(ModelServerEndpoint endpoint) {
        this.endpoint = endpoint;
        headerOverrides["Content-Type"] = "application/json";
    }

    protected string apiUrl() const => endpoint.apiUrl;

    Logger getLogger() => logger is null ? stdThreadLocalLog : logger;

    /// Checks if the server is up.
    bool healthCheck() const => true;

    /// Set up OpenAI style authentication, using a HTTP bearer token
    void setApiKey(string apiKey) {
        headerOverrides["Authorization"] = "Bearer " ~ apiKey;
    }

    protected LlamaResponse deserializeResp(string str) {
        return str.deserialize!LlamaResponse;
    }

    LlamaResponse sendReq(LlamaMessage[] history, LlamaToolDef[] apiToolDefs = []) {
        auto payload = LlamaReq(
            model: model,
            reasoningEffort: reasoningEffort,
            messages: history,
            tools: apiToolDefs,
        ).serializeToJson;
        getLogger().tracef("Sending v1 completions request: %s", payload);

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
            if (len == 0) {
                return len;
            }
            data[0 .. len] = m[0 .. len];
            payload = payload[len .. $];
            return len;
        };
        http.onReceive = (ubyte[] data) { builder.put(data); return data.length; };

        http.perform();

        auto str = cast(string) builder.data().idup;
        getLogger().tracef("Received response: %s", str);
        return deserializeResp(str);
    }
}

class LlamaServerModelServer : ModelServer {
    this(ModelServerEndpoint endpoint, string model = "") {
        super(endpoint);
        this.model = model;
    }

    override bool healthCheck() const {
        auto url = format!"%s://%s:%s/props"(endpoint.proto, endpoint.host, endpoint.port);
        try {
            get(url);
        } catch (CurlException exception) {
            return false;
        }
        return true;
    }
}

class GeminiModelServer : ModelServer {
    string apiKey;
    this(string apiKey, string model = "gemini-3.5-flash") {
        super(httpsEndpoint("generativelanguage.googleapis.com", 443, "/v1beta/openai/chat/completions"));
        this.apiKey = apiKey;
        this.model = model;
        setApiKey(apiKey);
    }

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
        } catch (Exception e) {
            return false;
        }
    }

    // Gemini has a crazy quirk, where the openai compatible endpoint returns an array of errors
    // instead of an error
    override LlamaResponse deserializeResp(string str) {
        try {
            return str.deserialize!LlamaResponse;
        } catch (SerdeException e) {
            auto resps = str.readGeminiErrorArray;
            if (resps == []) {
                throw new SessionException("Empty str returned");
            }
            return resps[0];
        }
    }
}

private LlamaResponse[] readGeminiErrorArray(string message) => message.deserialize!(LlamaResponse[]);

unittest {
    auto regr1 = `[{
      "error": {
        "code": 404,
        "message": "models/test-not-found is not found for API version v1main, or is not supported for `
        ~ `generateContent. Call ModelService.ListModels to see the list of available models and `
        ~ `their supported methods.",
        "status": "NOT_FOUND"
      }
    }]`;
    assert(regr1.readGeminiErrorArray().length == 1);
}

ModelServerEndpoint httpEndpoint(string host, ushort port = 80, string path = OPENAI_API_PATH)
    => ModelServerEndpoint("http", host, port, path);
ModelServerEndpoint httpsEndpoint(string host, ushort port = 443, string path = OPENAI_API_PATH)
    => ModelServerEndpoint("https", host, port, path);
