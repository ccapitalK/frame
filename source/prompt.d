module agent_harness.prompt;

import std.stdio;

import agent_harness.llamacpp_proto;

void printChat(LlamaMessage[] messages) {
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
            writeln("Agent: ", message.content);
            break;
        case "tool":
            writefln!"Tool(%s): %s"(message.toolCallId, message.content);
            break;
        default:
            writeln(message);
        }
    }
}

struct HistoryPrinter {
    LlamaMessage[] *history;
    size_t printedWatermark;
}

void printLog(ref HistoryPrinter printer) {
    printChat((*printer.history)[printer.printedWatermark .. $]);
    printer.printedWatermark = printer.history.length;
}
