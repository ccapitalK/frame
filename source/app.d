module agent_harness.app;

import std.conv;
import std.stdio;

import asdf;

import agent_harness.client;
import agent_harness.llamacpp_proto;
import agent_harness.prompt;
import agent_harness.tools;

ToolDef binopDef(alias f)(string name, string desc) => simpleToolDef(
    name,
    desc,
    [
        SimpleParam("a", "number", "First Number"),
        SimpleParam("b", "number", "Second Number"),
    ],
    wrapFuncWithJson!(f, Num2Req),
);

struct Num2Req {
    double a;
    double b;
}

ToolDef[] tools() {
    return [
        binopDef!add2("add2", "Add a and b"),
        binopDef!sub2("sub2", "Subtract b from a"),
    ];
}

double add2(Num2Req req) => req.a + req.b;

double sub2(Num2Req req) => req.a - req.b;

void main(string[] args) {
    string port = "8080";
    if (args.length > 1) {
        port = args[1];
    }
    auto host = ModelServer("localhost", port);
    if (!host.healthCheck()) {
        writeln("No healthy host, is your server running?");
        return;
    }
    host.toolSet = tools.makeToolSet();
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
        history.handleToolResponses(host.toolSet);
    }
    printer.printLog();
}
