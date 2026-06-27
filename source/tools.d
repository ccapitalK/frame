module agent_harness.tools;

import std.algorithm;
import std.array;
import std.typecons;

import asdf;

import agent_harness.llamacpp_proto;

struct ToolDef {
    LlamaToolDef apiToolDef;
    string delegate(string) method;
}

struct ToolSet {
    LlamaToolDef[] apiToolDefs;
    ToolDef[string] tools;
}

ToolSet makeToolSet(ToolDef[] defs) {
    ToolDef[string] tools;
    LlamaToolDef[] apiToolDefs;
    foreach (def; defs) {
        auto name = def.apiToolDef.function_.name;
        tools[name] = def;
        apiToolDefs ~= def.apiToolDef;
    }
    return ToolSet(
        apiToolDefs: apiToolDefs,
        tools: tools,
    );
}

string delegate(string) wrapFuncWithJson(alias f, Req)() {
    return (string v) {
        auto decoded = v.deserialize!Req;
        return f(decoded).serializeToJson;
    };
}

void handleToolResponses(ref LlamaMessage[] history, ToolSet toolSet) {
    auto lastMessage = history[$ - 1];
    if (lastMessage.toolCalls == []) {
        return;
    }
    foreach (call; lastMessage.toolCalls) {
        auto funcName = call.function_.name;
        auto argsJson = call.function_.argumentsJson;
        string resp;
        try {
            auto method = toolSet.tools[funcName].method;
            resp = method(argsJson);
        } catch(Exception e) {
            resp = "Internal error";
        }
        // TODO: Handle errors
        history ~= [
            LlamaMessage(role : "tool", toolCallId: call.id, content: resp)
        ];
    }
}

struct SimpleParam {
    string name;
    string type;
    string description;
}

ToolDef simpleToolDef(string name, string desc, SimpleParam[] params, string delegate(string) method) =>
    ToolDef(
        apiToolDef: LlamaToolDef("function", LlamaToolFunction(
            name : name,
            description: desc,
            LlamaToolParameters(
                "object",
                params.map!"a.name".array,
                params.map!(a => tuple(a.name, LlamaToolProperty(a.type, a.description))).assocArray,
            ),
        )),
        method: method,
    );
