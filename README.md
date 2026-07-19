# Frame - A hackable agent harness, for unsupervised automation

A hackable LLM harness library for D, for unattended jobs that need a bit of fleshy intelligence.

** Note: This library is still in development, the broad strokes of the api surface have been determined, but certain
aspects may change drastically in later releases (in particular, around authentication, history management and
protocol adaptors). There are some convenience features that will also be polished and cleaned up over time.
Continuations (the eventual solution for hierarchical planning/rewinding chats) are also still very experimental.**

## What is this

Frame is a hackable agent harness, for building robust automations that can run unsupervised, with only a bit of 
machine intelligence needed. Example use cases include simple NLP tasks, summarization of large datasets using simpler
models (to be then reviewed by more intelligent models), and simple "Ralph loops" with a constrained set of tools.

While this library is not meant for chat applications, it should be possible to build
a simple REPL on top of it for projects that need a chat interface.

## Model providers

Currently, this library targets the the openai completions v1 endpoint, without streaming. Integrations with the
following model providers have been tested:

- Gemini, using the OpenAI compatible legacy endpoint
- Llama-server (built from the official llama.cpp repo)
- Some third party openai compatible providers, that authorize using http bearer tokens

There is no current plan to support the streaming endpoint, since it adds complexity and doesn't provide any benefits
for unattended use cases.

## Examples

Wiring up the harness to be invoked from your code can be as simple as the following:


```d
import frame.agent;
import frame.client;
import frame.tool;

void main() {
    auto host = new ModelServer(ModelServerEndpoint("https", "localhost", 12_349, OPENAI_API_PATH));
    ToolDef[] tools = [ /* Your tools here */ ];
    auto agent = makeAgent(host, tools);
    agent.setupAgentSystemPrompt("You are helpful.");
    // This will invoke the llm repeatedly, until there are no more tool uses pending.
    agent.promptAsUser("Do my bidding", printOutput: false);
}
```

More examples can be found in `examples/`.

## Tool use

It is very easy to wire up custom tools to a `frame` agent.

```d
import std.algorithm : map;
import std.datetime;
import std.array;
import std.exception;
import std.file;

import frame.agent;
import frame.tool;

// Empty request type.
struct Empty {}

// Response from the "presence" Tool
struct PresenceResp {
    string[] files;
    string currentWorkingDirectory;
}

// Request for adding two numbers. No documentation is needed here, so we don't provide it
struct AddReq {
    double a;
    double b;
}

// Request to divide two integers. It makes sense to document v and d
struct DivisionReq {
    @ToolDoc("Dividend")
    int v;
    @ToolDoc("Divisor")
int d;
}

auto addTool = simpleToolDef!((AddReq req) => req.a + req.b)("add", "Add a to b");

auto divTool = simpleToolDef!((DivisionReq req) {
    // ToolExceptions are caught and presented back to the llm as a visible error. All other errors are reported
    // as an "Internal error", to make it harder to unintentionally leak runtime environment details.
    enforce(req.d != 0, new ToolException("Attempted to divide by zero"));
    return [req.v / req.d, req.v % req.d];
})("divide", "Divide v by d, returning [quotient, remainder]");

auto dateTool = simpleToolDef!((Empty _) => Clock.currTime.toISOString)("date", "Get current date and time");

auto presenceTool = simpleToolDef!(
    (Empty _) => PresenceResp(".".dirEntries(SpanMode.shallow).map!"a.name".array, getcwd)
)("presence", "Get the current working directory, and all files/folders in this directory");

auto allTools = [addTool, divTool, dateTool, presenceTool];
auto agent = modelServer.makeAgent(allTools);
```
