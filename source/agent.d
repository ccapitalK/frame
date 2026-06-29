module agent_harness.agent;

import std.exception;
import std.logger;
import std.stdio;

import agent_harness.client;
import agent_harness.history;
import agent_harness.llamacpp_proto;
import agent_harness.prompt;
import agent_harness.tool;

class Agent {
    ModelServer host;
    History history = new History();
    ToolSet toolSet;

    this(ModelServer host) {
        this.host = host;
    }
}

Agent makeAgent(ModelServer server, ToolDef[] tools=[], bool enableLogging=false) {
    auto agent = new Agent(server);
    if (!agent.host.healthCheck()) {
        throw new Exception("No healthy host, is your server running?");
    }
    if (enableLogging) {
        agent.host.logger = new FileLogger(stdout, LogLevel.trace);
    }
    agent.toolSet = tools.makeToolSet();
    return agent;
}

void setupAgentSystemPrompt(Agent agent, string prompt) {
    enforce(agent.history.messages == [], "System prompt must be at the start");
    agent.history.messages = [systemPrompt(prompt)];
}

LlamaMessage invokeAgentResponse(Agent agent) {
    auto toolSet = agent.toolSet;
    auto message = agent.host.sendReq(agent.history.messages, toolSet.apiToolDefs).choices[0].message;
    agent.history.messages ~= message;
    agent.history.messages.handleToolResponses(toolSet);
    return message;
}

LlamaMessage promptAsUser(Agent agent, string prompt) {
    agent.history.messages ~= userPrompt(prompt);
    return agent.invokeAgentResponse();
}

bool isEndOfAgentMessageSequence(LlamaMessage message) {
    return message.role == "assistant" && message.content != "" && message.toolCalls == [];
}

/// Default implementation of a standard agent loop, runs till the agent is "done".
void runUntilToolUsesAreDone(Agent agent) {
    while(true) {
        auto message = agent.invokeAgentResponse();
        if (message.isEndOfAgentMessageSequence) {
            break;
        }
        agent.history.printLog();
    }
    agent.history.printLog();
}
