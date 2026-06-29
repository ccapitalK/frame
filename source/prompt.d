module agent_harness.prompt;

import std.algorithm : min;
import std.format;
import std.stdio;

import agent_harness.llamacpp_proto;

enum Color { red = 31, green = 32, yellow = 33, blue = 34, magenta = 35, cyan = 36 }

string colorize(string s, Color c) {
    return format("\x1b[%dm%s\x1b[0m", cast(int) c, s);
}

// TODO(ccapitalk): This whole stack needs to be rethought a bit later down the line, especially for rewind.

void printChat(LlamaMessage[] messages) {
    string[string] ids;
    printChat(messages, ids);
}

void printChat(LlamaMessage[] messages, ref string[string] toolIdToParamMap) {
    foreach (message; messages) {
        switch (message.role) {
        case "system":
            writeln("System: ".colorize(Color.yellow), message.content);
            break;
        case "user":
            writeln("User: ".colorize(Color.green), message.content);
            break;
        case "assistant":
            if (message.reasoningContent != "") {
                writeln("Agent(Reasoning): ".colorize(Color.red), message.reasoningContent);
            }
            foreach (call; message.toolCalls) {
                string funcName = call.function_.name;
                string params = call.function_.argumentsJson;
                string id = call.id;
                toolIdToParamMap[id] = format!"%s(%s)"(funcName, params);
            }
            writeln("Agent: ".colorize(Color.blue), message.content);
            break;
        case "tool":
            auto params = message.toolCallId in toolIdToParamMap;
            enum fmtString = "Tool".colorize(Color.cyan) ~ ": %s = %s";
            writefln!fmtString(params ? *params : message.toolCallId, message.content);
            break;
        default:
            writeln(message);
        }
    }
}


/// Put this at the start of the history to provide a system prompt
LlamaMessage systemPrompt(string prompt) => LlamaMessage(role: "system", content: prompt);

LlamaMessage userPrompt(string prompt) => LlamaMessage(role: "user", content: prompt);
