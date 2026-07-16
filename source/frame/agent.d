module frame.agent;

import std.exception;
import std.logger;
import std.stdio;

import frame.client;
import frame.history;
import frame.llamacpp_proto;
import frame.prompt;
import frame.tool;

class Agent {
    ModelServer host;
    History history;
    ToolSet toolSet;

    this(ModelServer host) {
        this.host = host;
        this.history = new History();
    }
}

Agent makeAgent(ModelServer server, ToolDef[] tools = [], bool enableLogging = false) {
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
    auto resp = agent.host.sendReq(agent.history.messages, toolSet.apiToolDefs);
    if (resp.error !is null) {
        throw new SessionException("Error: " ~ resp.error.message);
    }
    auto message = resp.choices[0].message;
    agent.history.messages ~= message;
    agent.history.printLog();
    agent.history.handleToolResponses(toolSet);
    return message;
}

LlamaMessage promptAsUser(Agent agent, string prompt) {
    agent.history.messages ~= userPrompt(prompt);
    agent.history.printLog();
    return agent.invokeAgentResponse();
}

bool isEndOfAgentMessageSequence(LlamaMessage message) {
    bool isAssistant = message.role == "assistant";
    bool noToolCalls = message.toolCalls == [];
    // It's done, if there is a message, or if both content and reasoning are empty
    // (combined with no tool calls, that's a clear end of response chain)
    bool isDoneMessage = message.content != "" || message.reasoningContent == "";
    return isAssistant && noToolCalls && isDoneMessage;
}

/// Default implementation of a standard agent loop, runs till the agent is "done".
void runUntilToolUsesAreDone(Agent agent) {
    while (true) {
        auto message = agent.invokeAgentResponse();
        if (message.isEndOfAgentMessageSequence) {
            break;
        }
        agent.history.printLog();
    }
    agent.history.printLog();
}
