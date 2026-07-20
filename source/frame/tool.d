module frame.tool;

import std.algorithm;
import std.array;
import std.exception;
import std.traits;
import std.typecons;

import asdf;

import frame.history;
import frame.llamacpp_proto;

class ToolException: Exception {
    this(string message) {
        super(message);
    }
}

class TimeTravelException: Exception {
    this() {
        super("Program halted by non-linear passage of time");
    }
}

struct ToolDef {
    LlamaToolDef apiToolDef;
    bool mustBeLastInDispatch = false;
    string delegate(string) method;
}

ToolDef setMustBeLastInDispatch(ToolDef def) {
    def.mustBeLastInDispatch = true;
    return def;
}

struct ToolSet {
    LlamaToolDef[] apiToolDefs;
    ToolDef[string] tools;

    void addTool(ToolDef def) {
        auto name = def.apiToolDef.function_.name;
        enforce(name !in tools, "Tools must have unique names");
        tools[name] = def;
        apiToolDefs ~= def.apiToolDef;
    }

    void addTools(ToolDef[] defs) {
        foreach (def; defs) {
            addTool(def);
        }
    }
}

ToolSet makeToolSet(ToolDef[] defs) {
    ToolSet toolSet;
    toolSet.addTools(defs);
    return toolSet;
}

/// Pass through the string without escaping as parseable string, to reduce cognitive load of the llm.
string jsonCoerceToString()(string val) => val;

/// Otherwise make it into a string
string jsonCoerceToString(T)(T val) {
    return val.serializeToJson;
}

/// For the tool call pipeline, we need a function that takes a string and returns a string
private string delegate(string) wrapFuncForToolCall(alias f)() if (arity!f <= 1) {
    enum hasParam = arity!f == 1;
    enum hasReturn = !is(ReturnType!f == void);
    static if (hasParam) {
        alias Req = Parameters!f[0];
        static if (hasReturn) {
            return (string v) {
                Req decoded;
                try {
                    decoded = v.deserialize!Req;
                } catch (AsdfSerdeException e) {
                    return "Failed to parse input";
                }
                return f(decoded).jsonCoerceToString;
            };
        } else {
            return (string v) {
                Req decoded;
                try {
                    decoded = v.deserialize!Req;
                } catch (AsdfSerdeException e) {
                    return "Failed to parse input";
                }
                f(decoded);
                return "SUCCESS";
            };
        }
    } else {
        static if (hasReturn) {
            return (string _) => jsonCoerceToString(f());
        } else {
            return (string _) {
                f();
                return "SUCCESS";
            };
        }
    }
}

void handleToolResponses(History history, ToolSet toolSet) {
    auto lastMessage = history.messages[$ - 1];
    if (lastMessage.toolCalls == []) {
        return;
    }
    foreach (i, call; lastMessage.toolCalls) {
        auto funcName = call.function_.name;
        auto argsJson = call.function_.argumentsJson;
        string resp;
        try {
            auto def = funcName in toolSet.tools;
            if (!def) {
                throw new ToolException("No tool with that name");
            }
            if (def.mustBeLastInDispatch && i + 1 < lastMessage.toolCalls.length) {
                throw new ToolException("Must be last tool in parallel tool call dispatch");
            }
            auto method = def.method;
            resp = method(argsJson);
        } catch(TimeTravelException e) {
            // Time travel tool invoked. The tool has changed the history, and is responsible for keeping it coherent
            break;
        } catch(ToolException e) {
            // We trust these to be exposed to the llm  
            resp = "Error: " ~ e.msg;
        } catch(Exception e) {
            resp = "Internal error";
        }
        // Note: The llm agent will need to understand that an empty tool call reponse isn't actually empty.
        resp = resp == "" ? `""` : resp;
        history.messages ~= [
            LlamaMessage(role : "tool", toolCallId: call.id, content: resp)
        ];
        history.printLog();
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
string schemaType(T: bool)() => "boolean";
string schemaType(T: int)() => "integer";
string schemaType(T: double)() => "number";
string schemaType(T: string)() => "string";

SimpleParam[] extractParams(T)() if (isAggregateType!T) {
    SimpleParam[] params;
    enum fields = FieldNameTuple!T;
    static foreach (i; 0 .. fields.length) {{
        enum field = fields[i];
        enum qualifiedField = "T." ~ field;
        enum docFields = getUDAs!(mixin(qualifiedField), ToolDoc);
        static if (docFields.length > 0) {
            static assert(docFields.length <= 1, "Can't have multiple ToolDoc defs for " ~ qualifiedField);
            enum doc = docFields[0].description;
        } else {
            enum doc = "";
        }
        params ~= SimpleParam(field, schemaType!(typeof(mixin(qualifiedField))), doc);
    }}
    return params;
}

ToolDef simpleToolDef(alias f)(string name, string desc) if (arity!f <= 1) {
    static if (arity!f == 0) {
        static immutable SimpleParam[] params = [];
    } else {
        enum params = extractParams!(Parameters!f[0]);
    }
    auto toolParams = LlamaToolParameters(
        "object",
        params.map!"cast(string) a.name".array,
        params.map!(a => tuple(a.name, LlamaToolProperty(a.type, a.description))).assocArray,
    );
    return ToolDef(
        apiToolDef: LlamaToolDef("function", LlamaToolFunction(
            name : name,
            description: desc,
            parameters: toolParams,
        )),
        method: wrapFuncForToolCall!f,
    );
}
