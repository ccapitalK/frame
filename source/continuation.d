module frame.continuation;

import std.exception;

import frame.agent;
import frame.llamacpp_proto;
import frame.tool;

import asdf;

struct CallCcReq {
    @ToolDoc("Name of continuation to create")
    string name;
    @ToolDoc("Readable description of the task the continuation is for")
    string purpose;
}

struct CallCcResp {
    string restoreMessage;
    string continuationPurpose;
    size_t restoreCount;
}

struct RestoreContinuationReq {
    @ToolDoc("Name of continuation to restore")
    string name;
    @ToolDoc("Summary to resume continuation with, should be very descriptive (a paragraph or two)")
    string summary;
}

struct ContinuationFrame {
    string name;
    size_t index;
}

struct Continuation {
    string purpose;
    size_t index;
    size_t restoreCount;
}

class ContinuationManager {
    Agent agent;
    private Continuation[string] activeContinuations;
    private ContinuationFrame[] stack;
    private ToolDef[] toolDefs;

    this (Agent agent) {
        this.agent = agent;
        toolDefs = [
            simpleToolDef!((CallCcReq req) {
                enforce(req.name != "", new ToolException("Name can't be empty"));
                auto name = req.name;
                auto offset = agent.history.messages.length;

                activeContinuations[name] = Continuation(req.purpose, offset, 0);
                stack ~= ContinuationFrame(name, offset);

                return CallCcResp("Initial", req.purpose, 0);
            })(
                "callCCPrompts",
                "Create a continuation, that may be restored later. Must be last tool invocation ok assistant message",
            ),
            simpleToolDef!((RestoreContinuationReq req) {
                enforce(req.summary != "", new ToolException("Can't post empty summary"));
                auto continuation = req.name in activeContinuations;
                enforce(continuation != null, new ToolException("Continuation doesn't exist"));
                auto offset = continuation.index;
                auto purpose = continuation.purpose;
                ++continuation.restoreCount;

                string toolCallId = agent.history.messages[offset].toolCallId;
                agent.host.getLogger.trace("==================== REWINDING(" ~ req.name ~ ")");
                while (stack != [] && stack[$ - 1].index > offset) {
                    activeContinuations.remove(stack[$ - 1].name);
                    stack = stack[0 .. $ - 1];
                }

                agent.history.rewindTo(offset);
                auto content = CallCcResp(req.summary, purpose, continuation.restoreCount).serializeToJson;
                agent.history.messages ~= LlamaMessage(role: "tool", toolCallId: toolCallId, content: content);
                throw new TimeTravelException();
                return "";
            })(
                "restoreContinuation",
                "Restore a named continuation, with a summary of all important information after it to extract",
            ),
        ];
    }

    ToolDef[] tools() => toolDefs;
}
