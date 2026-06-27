module agent_harness.prompt;

import std.format;
import std.stdio;

import agent_harness.llamacpp_proto;

// TODO(ccapitalk): This whole stack needs to be rethought a bit later down the line, especially for rewind.

void printChat(LlamaMessage[] messages) {
    string[string] ids;
    printChat(messages, ids);
}

void printChat(LlamaMessage[] messages, ref string[string] toolIdToParamMap) {
    foreach (message; messages) {
        switch (message.role) {
        case "system":
            writeln("System: ", message.content);
            break;
        case "user":
            writeln("User: ", message.content);
            break;
        case "assistant":
            if (message.reasoningContent != "") {
                writeln("Agent(Reasoning): ", message.reasoningContent);
            }
            foreach (call; message.toolCalls) {
                string funcName = call.function_.name;
                string params = call.function_.argumentsJson;
                string id = call.id;
                toolIdToParamMap[id] = format!"%s(%s)"(funcName, params);
            }
            writeln("Agent: ", message.content);
            break;
        case "tool":
            auto params = message.toolCallId in toolIdToParamMap;
            writefln!"Tool(%s): %s"(params ? *params : message.toolCallId, message.content);
            break;
        default:
            writeln(message);
        }
    }
}

struct HistoryPrinter {
    LlamaMessage[] *history;
    string[string] toolCallIdsToParams;
    size_t printedWatermark;
}

void printLog(ref HistoryPrinter printer) {
    auto unprinted = (*printer.history)[printer.printedWatermark .. $];
    printChat(unprinted, printer.toolCallIdsToParams);
    printer.printedWatermark = printer.history.length;
}
