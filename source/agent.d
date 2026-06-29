module agent_harness.agent;

import std.logger;
import std.stdio;

import agent_harness.client;
import agent_harness.llamacpp_proto;
import agent_harness.prompt;
import agent_harness.tool;

// TODO: make this a class?
struct Agent {
    ModelServer host;
    LlamaMessage[] history;
    HistoryPrinter printer;
}

Agent *makeAgent(string url, string port, ToolDef[] tools=[], bool enableLogging=false) {
    auto agent = new Agent();
    agent.host = ModelServer(url, port);
    if (!agent.host.healthCheck()) {
        throw new Exception("No healthy host, is your server running?");
    }
    if (enableLogging) {
        agent.host.logger = new FileLogger(stdout, LogLevel.trace);
    }
    agent.host.toolSet = tools.makeToolSet();
    agent.printer = HistoryPrinter(&agent.history);
    return agent;
}

LlamaMessage invokeAgentResponse(Agent *agent) {
    auto message = agent.host.sendReq(agent.history).choices[0].message;
    agent.history ~= message;
    agent.history.handleToolResponses(agent.host.toolSet);
    return message;
}

LlamaMessage promptAsUser(Agent *agent, string prompt) {
    agent.history ~= userPrompt(prompt);
    return agent.invokeAgentResponse();
}

bool isEndOfAgentMessageSequence(LlamaMessage message) {
    return message.role == "assistant" && message.content != "" && message.toolCalls == [];
}

/// Default implementation of a standard agent loop, runs till the agent is "done".
void runNormalAgentLoop(Agent *agent) {
    while(true) {
        auto message = agent.invokeAgentResponse();
        if (message.isEndOfAgentMessageSequence) {
            break;
        }
        agent.printer.printLog();
    }
    agent.printer.printLog();
}
