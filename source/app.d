module agent_harness.app;

import std.array;
import std.algorithm;
import std.exception;
import std.file;
import std.stdio;

import agent_harness.agent;
import agent_harness.prompt;
import agent_harness.tools;

string[] readFileList(string fileListPath) {
    return fileListPath.readText().splitter('\n').filter!"a != []".array;
}

struct Empty {}

struct ViewRange {
    @ToolDoc("File to read from")
    string fileName;
    @ToolDoc("Offset to read starting from")
    size_t offset;
}

struct ViewRangeResponse {
    string response;
    size_t actualFileLength;
    size_t responseLength;
}

struct AddEntry {
    @ToolDoc("File to submit summary for")
    string filename;
    @ToolDoc("Summary of the file")
    string summary;
}

void main(string[] args) {
    string port = "12349";
    auto files = args[1].readFileList();
    string[string] summaries;
    auto remainingFiles() => files[].filter!(a => a !in summaries);
    bool hasSubmitted;
    auto tools = [
        simpleToolDef!((Empty _) => files[].filter!(a => a !in summaries).array)
            ("remainingFiles", "Return list of files yet to be summarized"),
        simpleToolDef!((ViewRange req) {
            writeln(req);
            enforce(files[].any!(a => a == req.fileName));
            auto text = req.fileName.readText();
            enforce(text.length >= req.offset);
            auto end = min(text.length, req.offset + 1024);
            return ViewRangeResponse(
                text[req.offset .. end],
                text.length,
                end - req.offset,
            );
        })("viewRange", "View a range of bytes in a file. Limits to at most 1024 in a single query"),
        simpleToolDef!((AddEntry req) {
            enforce(remainingFiles.any!(a => a == req.filename));
            summaries[req.filename] = req.summary;
            hasSubmitted = true;
            return "";
        })("submitSummary", "Submit a summary of a file"),
    ];
    auto agent = makeAgent("localhost", port, tools);
    agent.history = [systemPrompt(
        "You are an autonomous agent summarizing code files. You are running fully autonomously, do not prompt the user for more information."
    )];
    agent.history ~= userPrompt(
        "Pick a file to summarize, read through the file making notes to yourself out loud, then submit a summary of the file. "
    );
    while (remainingFiles.count > 0) {
        hasSubmitted = false;
        agent.printer.rewind(2);
        while (true && !hasSubmitted) {
            auto message = agent.invokeAgentResponse();
            if (message.isEndOfAgentMessageSequence) {
                break;
            }
            agent.printer.printLog();
        }
        agent.printer.printLog();
    }

    writeln(summaries);
}
