module frame.client;

import std.array;
import std.algorithm : canFind;
import std.conv;
import std.format;
import std.logger;
import std.net.curl;
import std.stdio;

import asdf;

import frame.llamacpp_proto;
import frame.tool;

enum SessionExceptionKind {
    general,
    conversationTooLong,
    badAuth,
    unknownModel,
    insufficientQuota,
}

class SessionException : Exception {
    SessionExceptionKind kind;
    this(string message, SessionExceptionKind kind = SessionExceptionKind.general) {
        super(message);
        this.kind = kind;
    }
}

SessionExceptionKind extractKind(LlamaResponseError error) {
    // OpenAi
    if (error.type == "invalid_request_error" && error.code == "context_length_exceeded") {
        return SessionExceptionKind.conversationTooLong;
    }
    // Llamacpp server
    if (error.code == 400 && error.type == "exceed_context_size_error") {
        return SessionExceptionKind.conversationTooLong;
    }
    // Gemini server (Haven't actually confirmed this one, can't trigger on free tier)
    if (error.code == 400 && error.message.canFind("exceeds the maximum number of tokens")) {
        return SessionExceptionKind.conversationTooLong;
    }

    if (error.code == 401 || error.code == "401") {
        return SessionExceptionKind.badAuth;
    }
    if (error.code == 404 || error.code == "404") {
        return SessionExceptionKind.unknownModel;
    }
    if (error.code == 429) {
        return SessionExceptionKind.insufficientQuota;
    }
    return SessionExceptionKind.general;
}

unittest {
    auto llamaCppTooLong = (`{"error":{"code":400,"message":"request (333307 tokens) exceeds the available `
        ~ `context size (32768 tokens), try increasing it","type":"exceed_context_size_error",`
        ~ `"n_prompt_tokens":333307,"n_ctx":32768}}`).deserialize!LlamaResponse;
    assert(llamaCppTooLong.error.extractKind == SessionExceptionKind.conversationTooLong);
    auto geminiInvalidModelName = (`{
      "error": {
        "code": 404,
        "message": "models/test-not-found is not found for API version v1main, or is not supported for `
        ~ `generateContent. Call ModelService.ListModels to see the list of available models and `
        ~ `their supported methods.",
        "status": "NOT_FOUND"
      }
    }`).deserialize!LlamaResponse;
    assert(geminiInvalidModelName.error.extractKind == SessionExceptionKind.unknownModel);
    auto geminiInsufficientQuota = (`{
      "error": {
        "code": 429,
        "message": "You exceeded your current quota, please check your plan and billing details. For `
        ~ `more information on this error, head to: https://ai.google.dev/gemini-api/docs/rate-limits. `
        ~ `To monitor your current usage, head to: https://ai.dev/rate-limit. \n* Quota exceeded for `
        ~ `metric: generativelanguage.googleapis.com/generate_content_free_tier_input_token_count, `
        ~ `limit: 250000, model: gemini-3.1-flash-lite\nPlease retry in 55.460643341s.",
        "status": "RESOURCE_EXHAUSTED",
        "details": []
      }
    }`).deserialize!LlamaResponse;
    assert(geminiInsufficientQuota.error.extractKind == SessionExceptionKind.insufficientQuota);
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
