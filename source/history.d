module agent_harness.history;

import std.algorithm;

import agent_harness.llamacpp_proto;
import agent_harness.prompt;

class History {
    LlamaMessage[] messages;
    string[string] toolCallIdsToParams;
    size_t printedWatermark;

    void printLog() {
        auto unprinted = messages[printedWatermark .. $];
        printChat(unprinted, toolCallIdsToParams);
        printedWatermark = messages.length;
    }

    void rewindTo(size_t offset) {
        if (messages.length <= offset) {
            return;
        }
        messages = messages[0 .. offset];
        printedWatermark = min(printedWatermark, offset);
    }
}
