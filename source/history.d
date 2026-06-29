module frame.history;

import std.algorithm;

import frame.llamacpp_proto;
import frame.prompt;

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
