module agent_harness.app;

import std.conv;
import std.stdio;

import asdf;

import agent_harness.client;
import agent_harness.llamacpp_proto;

LlamaToolDef[] tools() {
    return [
        LlamaToolDef("function", LlamaToolFunction(
            name : "add2",
            description: "Add 2 numbers and return the result",
            LlamaToolParameters(
                "object",
                ["a", "b"],
                [
                    "a": LlamaToolProperty("number", "First number"),
                    "b": LlamaToolProperty("number", "Second number"),
                ],
            ),
        )),
    ];
}

struct AddReq {
    double a;
    double b;
}

double add2(AddReq req) {
    return req.a + req.b;
}

void handleToolResponses(ref LlamaMessage[] history) {
    auto lastMessage = history[$ - 1];
    if (lastMessage.toolCalls == []) {
        return;
    }
    foreach (call; lastMessage.toolCalls) {
        history ~= [
            LlamaMessage(role : "tool", toolCallId: call.id, content: "0")
        ];
    }
}

void main(string[] args) {
    string port = "8080";
    if (args.length > 1) {
        port = args[1];
    }
    auto host = ModelServer("localhost", port);
    host.tools = tools;
    auto history = [systemPrompt("You are helping me test my llm harness")];
    history ~= userPrompt("Test the tools by invoking them, tell me if they are wrong");
    history ~= host.sendReq(history) .choices[0].message;
    history.handleToolResponses();
    history ~= host.sendReq(history).choices[0].message;
    foreach (message; history) {
        writeln(message);
    }
}
