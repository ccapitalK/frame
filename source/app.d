module agent_harness.app;

import std.conv;
import std.logger;
import std.stdio;

import asdf;

import agent_harness.client;
import agent_harness.llamacpp_proto;
import agent_harness.prompt;
import agent_harness.tools;

struct Num2Req {
    @ToolDoc("First number")
    double a;
    @ToolDoc("Second number")
    double b;
}

ToolDef[] tools() {
    return [
        simpleToolDef!((Num2Req req) => req.a + req.b)("add2", "Add a and b"),
        simpleToolDef!((Num2Req req) => req.a - req.b)("sub2", "Subtract b from a"),
    ];
}

void main(string[] args) {
    string port = "12349";
    if (args.length > 1) {
        port = args[1];
    }
    auto host = ModelServer("localhost", port);
    if (!host.healthCheck()) {
        writeln("No healthy host, is your server running?");
        return;
    }
    host.toolSet = tools.makeToolSet();
    host.logger = new FileLogger(stdout, LogLevel.trace);
    LlamaMessage[] history;
    history ~= [systemPrompt("You are helping me test my llm harness")];
    history ~= userPrompt("Test the tools extensively, including edge case inputs (what happens if you try to avoid the schema?"
            ~ " Figure out if the harness is preventing you from breaking away from the schema)");
    auto printer = HistoryPrinter(&history);
    printer.printLog();
    while(true) {
        auto message = host.sendReq(history) .choices[0].message;
        history ~= message;
        if (message.content != "" && message.toolCalls == []) {
            break;
        }
        history.handleToolResponses(host.toolSet);
        printer.printLog();
    }
    printer.printLog();
}
