module agent_harness.tools;

import std.algorithm;
import std.array;
import std.traits;
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

private string delegate(string) wrapFuncWithJson(alias f)() if (arity!f == 1) {
    alias Req = Parameters!f[0];
    return (string v) {
        Req decoded;
        try {
            decoded = v.deserialize!Req;
        } catch (AsdfSerdeException e) {
            return "Failed to parse input";
        }
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

struct ToolDoc {
    string description;

    this(string description) {
        this.description = description;
    }
}

/// schemaType!T determines the corresponding json schema type for basic type T
string schemaType(T: int)() => "number";
string schemaType(T: double)() => "number";
string schemaType(T: string)() => "string";

SimpleParam[] extractParams(T)() if (isAggregateType!T) {
    SimpleParam[] params;
    enum fields = FieldNameTuple!T;
    static foreach (i; 0 .. fields.length) {{
        enum field = fields[i];
        enum qualifiedField = "T." ~ field;
        enum docFields = getUDAs!(mixin(qualifiedField), ToolDoc);
        static assert(docFields.length == 1, "Broken ToolDoc for " ~ qualifiedField);
        params ~= SimpleParam(field, schemaType!(typeof(mixin(qualifiedField))), docFields[0].description);
    }}
    return params;
}

ToolDef simpleToolDef(alias f)(string name, string desc) if (arity!f == 1) {
    enum params = extractParams!(Parameters!f[0]);
    auto toolParams = LlamaToolParameters(
        "object",
        params.map!"a.name".array,
        params.map!(a => tuple(a.name, LlamaToolProperty(a.type, a.description))).assocArray,
    );
    return ToolDef(
        apiToolDef: LlamaToolDef("function", LlamaToolFunction(
            name : name,
            description: desc,
            parameters: toolParams,
        )),
        method: wrapFuncWithJson!f,
    );
}
