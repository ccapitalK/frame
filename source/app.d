module agent_harness.app;

import std.conv;
import std.stdio;

import asdf;

import agent_harness.client;
import agent_harness.llamacpp_proto;
import agent_harness.prompt;

ToolDef add2Def() =>
    ToolDef(
        apiToolDef: LlamaToolDef("function", LlamaToolFunction(
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
        method: wrapFuncWithJson!(add2, AddReq),
    );

ToolDef[] tools() {
    return [
        add2Def,
    ];
}

struct AddReq {
    double a;
    double b;
}

double add2(AddReq req) {
    return req.a + req.b;
}

void main(string[] args) {
    string port = "8080";
    if (args.length > 1) {
        port = args[1];
    }
    auto toolSet = tools.makeToolSet();
    auto host = ModelServer("localhost", port);
    host.tools = toolSet.apiToolDefs;
    LlamaMessage[] history;
    history ~= [systemPrompt("You are helping me test my llm harness")];
    history ~= userPrompt("Test the tools extensively");
    auto printer = HistoryPrinter(&history);
    while(true) {
        auto message = host.sendReq(history) .choices[0].message;
        history ~= message;
        if (message.content != "" && message.toolCalls == []) {
            break;
        }
        printer.printLog();
        history.handleToolResponses(toolSet);
    }
    printer.printLog();
}
