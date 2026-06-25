module agent_harness.ollama_proto;

import asdf;

struct OllamaToolCall {
}

struct OllamaMessage {
    string role;
    string content;

    @serdeOptional
    @serdeIgnoreOutIf!"a == []"
    OllamaToolCall[] toolcall;

    @serdeOptional
    @serdeIgnoreOutIf!"a == []"
    string tool_name;
}

struct OllamaToolProperty {
    string type;
    string description;
}

struct OllamaToolParameters {
    string type;
    string[] required;
    OllamaToolProperty[string] properties;
}

struct OllamaToolFunction {
    string name;
    string description;
    OllamaToolParameters parameters;
}

struct OllamaToolDef {
    string type;
    @serdeKeys("function")
    OllamaToolFunction function_;
}

struct OllamaReqOptions {
    double temperature = 0;
}

struct OllamaReq {
    string model;
    bool stream;
    bool think;
    string keep_alive = "3m";
    OllamaReqOptions options;
    OllamaMessage[] messages;
    OllamaToolDef[] tools;
}

struct OllamaResponse {
    OllamaMessage message;
    bool done;
    string done_reason;
}

unittest {
    import std.stdio;

    auto req1 = `{
  "model": "qwen3:8b",
  "stream": false,
  "think": false,
  "keep_alive": "30m",
  "options": { "temperature": 0 },
  "messages": [
    {"role": "user", "content": "What is the temperature in Sydney?"}
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_temperature",
        "description": "Get the current temperature for a city",
        "parameters": {
          "type": "object",
          "required": ["city"],
          "properties": {
            "city": {"type": "string", "description": "The name of the city"}
          }
        }
      }
    }
  ]
}`;
    auto expected1 = OllamaReq("qwen3:8b", false, false, "30m", OllamaReqOptions(0), [
        OllamaMessage("user", "What is the temperature in Sydney?", [], "")
    ], [
        OllamaToolDef(
            "function",
            OllamaToolFunction(
                "get_temperature",
                "Get the current temperature for a city",
                OllamaToolParameters(
                    "object",
                    ["city"],
                    ["city": OllamaToolProperty("string", "The name of the city")]
                )
            )
        )
    ]);
    assert(req1.deserialize!OllamaReq == expected1);

    auto resp1 = `{"model":"qwen3:8b","created_at":"2026-06-25T02:26:53.241191951Z","message":{"role":"assistant",`
        ~ ` "content":"I am Qwen, a large language model developed by Alibaba Cloud. I can assist with a wide range `
        ~ `of tasks, from answering questions and creating content to providing information and engaging in`
        ~ ` conversations. How can I help you today?"},"done":true,"done_reason":"stop","total_duration":1071525193,`
        ~ `"load_duration":206436120,"prompt_eval_count":149,"prompt_eval_duration":26072000,"eval_count":46,`
        ~ `"eval_duration":836679000}`;
    auto expected2 = OllamaResponse(OllamaMessage(
                "assistant",
                `I am Qwen, a large language model developed by Alibaba Cloud. I can assist with a wide range of `
                ~ `tasks, from answering questions and creating content to providing information and engaging in `
                ~ `conversations. How can I help you today?`, [], ""), true, "stop");
    assert(resp1.deserialize!OllamaResponse == expected2);
}
