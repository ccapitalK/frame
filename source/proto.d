module agent_harness.proto;

import asdf;

struct OllamaToolCall {
}

struct OllamaMessage {
    string role;
    string content;
    @serdeOptional
    OllamaToolCall[] toolcall;
    @serdeOptional
    string tool_name;
    // TODO: Tool calls
}

struct OllamaToolDef {
    string type;
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
    /*"tools": [
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
  ]*/
}

struct OllamaResponse {
    OllamaMessage message;
    bool done;
    string done_reason;
}

unittest {
    import std.stdio;

    enum example1 = `{
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

    auto decoded1 = example1.deserialize!OllamaReq;
    writeln(decoded1);
}
