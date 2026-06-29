module file_summarizer.app;

import std.array;
import std.algorithm;
import std.conv;
import std.exception;
import std.file;
import std.stdio;

import frame.agent;
import frame.client;
import frame.prompt;
import frame.tool;

struct Empty {}

struct ViewRange {
    @ToolDoc("File to read from")
    string filename;
    @ToolDoc("Offset to read starting from")
    size_t offset;
}

struct ViewRangeResponse {
    string response;
    size_t actualFileLength;
    size_t[2] responseWindow;
}

struct AddEntry {
    @ToolDoc("File to submit concept against")
    string filename;
    @ToolDoc("Concept being introduced")
    string concept;
}

struct DoneFile {
    @ToolDoc("File to claim fully noted")
    string filename;
}

void main(string[] args) {
    // Setup tools
    auto files = args[1].readText().splitter('\n').filter!"a != []".array;
    string[][string] concepts;
    auto remainingFiles() => files[].filter!(a => a !in concepts);
    void[0][string] doneFiles;
    auto tools = [
        simpleToolDef!((Empty _) => remainingFiles.array)
            ("remainingFiles", "Return list of files yet to be summarized"),
        simpleToolDef!((ViewRange req) {
            enforce(files[].any!(a => a == req.filename));
            auto text = req.filename.readText();
            enforce(text.length >= req.offset);
            auto end = min(text.length, req.offset + 1024);
            return ViewRangeResponse(
                text[req.offset .. end],
                text.length,
                [req.offset, end],
            );
        })("viewRange", "View a range of bytes in a file. Limits to at most 1024 in a single query"),
        simpleToolDef!((AddEntry req) {
            enforce(files.any!(a => a == req.filename));
            concepts[req.filename] ~= req.concept;
            return "";
        })("addConcept", "Note a concept introduced in a file"),
        simpleToolDef!((DoneFile req) {
            enforce(req.filename !in doneFiles);
            doneFiles[req.filename] = [];
            return "";
        })("doneFile", "Submit that a file has been completely read, with all concepts noted."),
    ];

    // Setup agent
    ushort port = args.length > 2 ? args[1].to!ushort : 12_349;
    auto host = new ModelServer(httpEndpoint("localhost", port));
    auto agent = makeAgent(host, tools);

    // Configure agent
    agent.setupAgentSystemPrompt(
        `You are an autonomous agent summarizing code files. You are running fully autonomously, do not prompt the user
        for more information. Make sure that you have read the entire file before claiming you are done reading it. 
        Do not try to present concepts to the user directly, all harvested information must be sent through the tools.`
    );
    agent.promptAsUser(
        "Pick a file to summarize, read through the file, and note all important concepts introduced by that file."
        ~ "Always mark files as done with the doneFile tool once you have finished noting concepts for a specific file. "
    );

    // Run agent
    while (remainingFiles.count > 0) {
        auto numDone = doneFiles.length;
        writeln("==================== REWINDING ====================");
        while (doneFiles.length <= numDone) {
            auto message = agent.invokeAgentResponse();
            if (message.isEndOfAgentMessageSequence) {
                break;
            }
            agent.history.printLog();
        }
        agent.history.printLog();
    }

    // Print results
    foreach (file; concepts.keys) {
        writeln("# ", file);
        writeln();
        foreach (concept; concepts[file]) {
            writeln("- ", concept);
        }
        writeln();
    }
}
