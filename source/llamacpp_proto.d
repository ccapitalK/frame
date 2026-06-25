module agent_harness.llamacpp_proto;

import asdf;

//         "type": "function",
//         "function": {
//           "name": "get_temperature",
//           "arguments": "{\"city\": \"Sydney\"}"
//         },
struct LlamaToolFunctionCall {
    string name;

    @serdeKeys("arguments")
    string argumentsJson;
}

struct LlamaToolCall {
    string type;

    @serdeKeys("function")
    LlamaToolFunctionCall function_;
}

struct LlamaMessage {
    string role;
    string content;

    @serdeOptional
    @serdeKeys("reasoning_content")
    @serdeIgnoreOutIf!"a == []"
    string reasoningContent;

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
    bool stream;
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
  "tools": [{"type":"function","function":{
    "name":"get_temperature",
    "description": "Get the current temperature for a city",
    "parameters":{"type":"object","required":["city"],
      "properties":{"city":{"type":"string", "description":  "The name of the city"}}}}}],
  "temperature": 0
}`;
    auto expected1 = LlamaReq("", 0, false, [
        LlamaMessage("user", "temp in Sydney?", "", [])
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
                "assistant",
                "",
                `Okay, the user is asking for the temperature in Sydney. Let me check the tools available. There's a `
                ~ `function called get_temperature that requires the city parameter. Since the user mentioned Sydney, `
                ~ `I need to call that function with the city set to Sydney. I'll make sure to format the tool call `
                ~ `correctly within the XML tags.` ~ '\n',
                [LlamaToolCall("function", LlamaToolFunctionCall("get_temperature", "{\"city\": \"Sydney\"}"))]
            )
        )]);
    assert(resp1.deserialize!LlamaResponse == expected2);
}
