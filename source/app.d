module agent_harness.app;

import std.stdio;

import agent_harness.agent;
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
    auto agent = makeAgent("localhost", port, tools);
    agent.history ~= [systemPrompt("You are helping me test my llm harness")];
    agent.history ~= userPrompt("Test the tools extensively, including edge case inputs (what happens if you try to avoid the schema?"
            ~ " Figure out if the harness is preventing you from breaking away from the schema)");
    agent.runNormalAgentLoop();
}
