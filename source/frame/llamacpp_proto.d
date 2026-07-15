module frame.llamacpp_proto;

import asdf;

struct LlamaToolFunctionCall {
    string name;

    @serdeKeys("arguments")
    string argumentsJson;
}

class ExtraContent {
    static class GoogleExtraContent {
        @serdeKeys("thought_signature")
        string thoughtSignature;
    }

    @serdeOptional
    GoogleExtraContent google;
}

struct LlamaToolCall {
    string type;

    string id;

    @serdeOptional
    @serdeIgnoreOutIf!"a is null"
    @serdeKeys("extra_content")
    ExtraContent extraContent;

    @serdeKeys("function")
    LlamaToolFunctionCall function_;
}

struct LlamaMessage {
    string role;

    @serdeOptional
    @serdeIgnoreOutIf!"a == []"
    string content;

    @serdeOptional
    @serdeKeys("reasoning_content")
    @serdeIgnoreOutIf!"a == []"
    string reasoningContent;

    @serdeOptional
    @serdeKeys("tool_call_id")
    @serdeIgnoreOutIf!"a == []"
    string toolCallId;

    @serdeOptional
    @serdeKeys("tool_calls")
    @serdeIgnoreOutIf!"a == []"
    LlamaToolCall[] toolCalls;
}

struct LlamaToolProperty {
    string type;
    string description;
}

struct LlamaToolParameters {
    string type;
    string[] required;
    LlamaToolProperty[string] properties;
}

struct LlamaToolFunction {
    string name;
    string description;
    LlamaToolParameters parameters;
}

struct LlamaToolDef {
    string type;
    @serdeKeys("function")
    LlamaToolFunction function_;
}

struct LlamaReq {
    @serdeOptional
    @serdeIgnoreOutIf!"a == []"
    string model;
    double temperature = 0;

    @serdeOptional
    @serdeIgnoreOutIf!"a == []"
    @serdeKeys("reasoning_effort")
    string reasoningEffort;

    @serdeOptional
    bool stream;

    @serdeKeys("parallel_tool_calls")
    bool parallelToolCalls = true;
    LlamaMessage[] messages;
    LlamaToolDef[] tools;
}

struct LlamaResponseChoice {
    string finish_reason;
    LlamaMessage message;
}

struct LlamaResponse {
    LlamaResponseChoice[] choices;
}

unittest {
    import std.stdio;

    auto req1 = `{
  "messages": [{"role":"user","content":"temp in Sydney?"}],
  "parallel_tool_calls": true,
  "tools": [{"type":"function","function":{
    "name":"get_temperature",
    "description": "Get the current temperature for a city",
    "parameters":{"type":"object","required":["city"],
      "properties":{"city":{"type":"string", "description":  "The name of the city"}}}}}],
  "temperature": 0
}`;
    auto expected1 = LlamaReq("", 0, "", false, true, [
        LlamaMessage("user", "temp in Sydney?", "", "", [])
    ], [
        LlamaToolDef(
            "function",
            LlamaToolFunction(
                "get_temperature",
                "Get the current temperature for a city",
                LlamaToolParameters(
                    "object",
                    ["city"],
                    ["city": LlamaToolProperty("string", "The name of the city")]
                )
            )
        )
    ]);
    assert(req1.deserialize!LlamaReq == expected1);
    auto resp1 = `{"choices":[{"finish_reason":"tool_calls","index":0,"message":{"role":"assistant","content":"",`
        ~ `"reasoning_content":"Okay, the user is asking for the temperature in Sydney. Let me check the tools `
        ~ `available. There's a function called get_temperature that requires the city parameter. Since the user `
        ~ `mentioned Sydney, I need to call that function with the city set to Sydney. I'll make sure to format the `
        ~ `tool call correctly within the XML tags.\n","tool_calls":[{"type":"function","function":{"name":`
        ~ `"get_temperature","arguments":"{\"city\": \"Sydney\"}"},"id":"iPI6WsqO9K1rzTKlu1MLOz1BeEMOz8Ef"}]}}],`
        ~ `"created":1782395677,"model":"qwen3-8b.gguf","system_fingerprint":"b9796-60bc8866b","object":` 
        ~ `"chat.completion","usage":{"completion_tokens":91,"prompt_tokens":143,"total_tokens":234,` 
        ~ `"prompt_tokens_details":{"cached_tokens":142}},"id":"chatcmpl-LaeDT8jNCfbiSQrwnfHHDutXpHxuJJtx",`
        ~ `"timings":{"cache_n":142,"prompt_n":1,"prompt_ms":33.296,"prompt_per_token_ms":33.296,"prompt_per_second"`
        ~ `:30.0336376741951,"predicted_n":91,"predicted_ms":1484.502,"predicted_per_token_ms":16.31320879120879,`
        ~ `"predicted_per_second":61.300018457368196}}`;
    auto expected2 = LlamaResponse([
        LlamaResponseChoice(
            "tool_calls",
            LlamaMessage(
                role: "assistant",
                content: "",
                reasoningContent: `Okay, the user is asking for the temperature in Sydney. Let me check the tools `
                ~ `available. There's a function called get_temperature that requires the city parameter. Since the`
                ~ ` user mentioned Sydney, I need to call that function with the city set to Sydney. I'll make sure`
                ~ ` to format the tool call correctly within the XML tags.` ~ '\n',
                toolCallId: "",
                [LlamaToolCall("function", "iPI6WsqO9K1rzTKlu1MLOz1BeEMOz8Ef", null,
                    LlamaToolFunctionCall("get_temperature", "{\"city\": \"Sydney\"}"))]
            )
        )
    ]);
    assert(resp1.deserialize!LlamaResponse == expected2);

    // Regression test, deserializing this shouldn't crash
    enum reg1 = `{"choices":[{"finish_reason":"tool_calls","index":0,"message":{"content":"I am an AI assistant `
        ~ `designed to interact with you through this agent harness.\n\n### Who I am and what I see\nI am a large `
            ~ `language model trained by Google. Regarding what I \"see,\" I do not have eyes or access to your `
            ~ `physical environment. I only \"see\" the text and data you provide in this conversation window. I am `
            ~ `aware of the tools that have been made available to me by the system configuration.\n\n### Tools I can `
            ~ "call\\nI have access to the following tools:\\n*   **`add(a, b)`**: Adds two numbers together.\\n*   **"
            ~ "`sub(a, b)`**: Subtracts the second number from the "
            ~ `first.\n\n---\n\n### Testing the tools\n\nI will now perform a test calculation for each tool.\n\n`
            ~ `**Test 1: Addition**\nI will add 15 and 27.\n","role":"assistant","tool_calls":[{"extra_content":`
            ~ `{"google":{"thought_signature":"REDACTED_TEST_DATA"}},`
            ~ `"function":{"arguments":"{\"a\":15,\"b\":27}","name":"add"},"id":"bcBxLAM6","type":`
            ~ `"function"}]}}],"created":1783244216,"id":"tyVKatSQF4T_juMPxPPJmQo","model":"gemini-3.1-flash-lite",`
            ~ `"object":"chat.completion","usage":{"completion_tokens":198,"prompt_tokens":161,"total_tokens":359}}`;
    reg1.deserialize!LlamaResponse;
}
