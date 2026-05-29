import { accessSync, constants } from "node:fs";
import { basename, delimiter, normalize } from "node:path";
import { spawn } from "node:child_process";
import { joinSession } from "@github/copilot-sdk/extension";

// Prototype port of https://github.com/ekroon/copilot-catalog/tree/main/plugins/copilot-cmux
// Original hook script: plugins/copilot-cmux/scripts/cmux_notify.py

const MAX_BODY_LENGTH = 180;
const INTERACTIVE_TOOL_NAMES = new Set(["ask_user", "exit_plan_mode"]);
const DEFAULT_CMUX_BUNDLE_ID = "com.cmuxterm.app";
const STATUS_KEY = "copilot_cli";
const LEGACY_STATUS_KEYS = ["intent", "attention", "running", "claude_code"];

const state = {
    started: false,
    title: "",
    lastIntent: "",
    lastAttention: "",
    lastNotification: null,
    lastCommands: [],
    lastError: "",
    pendingInteraction: false,
};

const handledToolStarts = new Set();
const handledToolCompletes = new Set();

function normalizeBody(text) {
    return String(text ?? "").split(/\s+/).filter(Boolean).join(" ").slice(0, MAX_BODY_LENGTH);
}

function recordCommand(summary, result) {
    state.lastCommands.push({
        summary,
        ok: Boolean(result?.ok),
        code: result?.code ?? null,
        error: result?.error || "",
    });
    state.lastCommands = state.lastCommands.slice(-10);
    if (!result?.ok && result?.error) {
        state.lastError = result.error;
    }
}

function findExecutable(name) {
    for (const dir of (process.env.PATH || "").split(delimiter)) {
        if (!dir) continue;
        const candidate = `${dir}/${name}`;
        try {
            accessSync(candidate, constants.X_OK);
            return candidate;
        } catch {
            // Continue searching PATH.
        }
    }
    return "";
}

function resolveCmuxBinary() {
    const preferred = "/Applications/cmux.app/Contents/Resources/bin/cmux";
    try {
        accessSync(preferred, constants.X_OK);
        return preferred;
    } catch {
        return findExecutable("cmux");
    }
}

function getWorkspaceRef() {
    for (const key of ["CMUX_WORKSPACE_ID", "CMUX_WORKSPACE_REF"]) {
        const value = process.env[key];
        if (typeof value === "string" && value.trim()) return value.trim();
    }
    return "";
}

function runCommand(command, args, options = {}) {
    const timeoutMs = options.timeoutMs ?? 3000;
    return new Promise((resolve) => {
        let stdout = "";
        let stderr = "";
        let finished = false;

        const child = spawn(command, args, { stdio: ["pipe", "pipe", "pipe"] });
        const timer = setTimeout(() => {
            if (finished) return;
            finished = true;
            child.kill("SIGTERM");
            resolve({ ok: false, code: null, stdout, stderr, error: "timeout" });
        }, timeoutMs);

        child.stdout.on("data", (chunk) => {
            stdout += chunk.toString();
        });
        child.stderr.on("data", (chunk) => {
            stderr += chunk.toString();
        });
        child.on("error", (error) => {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            resolve({ ok: false, code: null, stdout, stderr, error: error.message });
        });
        child.on("close", (code) => {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            resolve({ ok: code === 0, code, stdout, stderr, error: code === 0 ? "" : stderr || `exit ${code}` });
        });

        if (typeof options.input === "string") {
            child.stdin.write(options.input);
        }
        child.stdin.end();
    });
}

async function runCmux(args, options = {}) {
    const cmux = resolveCmuxBinary();
    if (!cmux) {
        const result = { ok: false, code: null, stdout: "", stderr: "", error: "cmux not found" };
        recordCommand(`cmux ${args.join(" ")}`, result);
        return result;
    }

    const result = await runCommand(cmux, args, options);
    recordCommand(`cmux ${args.join(" ")}`, result);
    return result;
}

async function updateWorkspaceTitle(title) {
    return runCmux(["rename-workspace", title]);
}

async function setStatus(kind, message, extraArgs = []) {
    return runCmux(["set-status", kind, message, ...extraArgs]);
}

async function clearStatus(kind) {
    return runCmux(["clear-status", kind]);
}

async function clearNotifications() {
    return runCmux(["clear-notifications"]);
}

async function clearLegacyStatuses() {
    await Promise.all(LEGACY_STATUS_KEYS.map((key) => clearStatus(key)));
}

async function setCopilotStatus(message, extraArgs = []) {
    return setStatus(STATUS_KEY, message, extraArgs);
}

async function clearCopilotStatus() {
    return clearStatus(STATUS_KEY);
}

function findFirstString(payload, keys) {
    const stack = [payload];
    while (stack.length > 0) {
        const current = stack.pop();
        if (!current || typeof current !== "object" || Array.isArray(current)) continue;

        for (const key of keys) {
            const value = current[key];
            if (typeof value === "string" && value.trim()) return value.trim();
        }

        for (const value of Object.values(current)) {
            if (value && typeof value === "object") {
                if (Array.isArray(value)) {
                    for (const item of value) {
                        if (item && typeof item === "object") stack.push(item);
                    }
                } else {
                    stack.push(value);
                }
            }
        }
    }
    return "";
}

function extractSessionTitle(payload) {
    return findFirstString(payload, ["sessionTitle", "session_title", "sessionName", "session_name"]);
}

function extractWorkingDirectory(payload) {
    return (
        findFirstString(payload, [
            "cwd",
            "workingDirectory",
            "working_directory",
            "projectPath",
            "project_path",
            "workspacePath",
            "workspace_path",
            "directory",
        ]) ||
        process.env.PWD ||
        process.cwd()
    );
}

function extractProjectName(payload) {
    const directory = extractWorkingDirectory(payload);
    if (!directory) return "";
    const normalized = normalize(directory);
    return basename(normalized) || normalized;
}

function buildWorkspaceTitle(payload) {
    const sessionTitle = extractSessionTitle(payload);
    const projectName = extractProjectName(payload);
    if (sessionTitle && projectName) return `${projectName} — ${sessionTitle}`;
    return projectName || sessionTitle || "";
}

function buildContextSubtitle(payload) {
    const sessionTitle = extractSessionTitle(payload);
    const projectName = extractProjectName(payload);
    if (sessionTitle && projectName) return normalizeBody(`${sessionTitle} — ${projectName}`);
    return normalizeBody(sessionTitle || projectName);
}

function parseToolArgs(toolArgs) {
    if (toolArgs && typeof toolArgs === "object" && !Array.isArray(toolArgs)) return toolArgs;
    if (typeof toolArgs === "string" && toolArgs.trim()) {
        try {
            const parsed = JSON.parse(toolArgs);
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed;
        } catch {
            return {};
        }
    }
    return {};
}

function hasInteractionMarkers(toolArgs) {
    if (typeof toolArgs.question === "string" && toolArgs.question.trim()) return true;
    for (const key of ["choices", "actions"]) {
        if (Array.isArray(toolArgs[key]) && toolArgs[key].length > 0) return true;
    }
    for (const key of ["recommendedAction", "recommended_action"]) {
        if (typeof toolArgs[key] === "string" && toolArgs[key].trim()) return true;
    }
    return false;
}

function isInteractiveToolUse(toolName, toolArgs) {
    return INTERACTIVE_TOOL_NAMES.has(toolName) || hasInteractionMarkers(toolArgs);
}

function defaultInteractionSubtitle(toolName) {
    if (toolName === "ask_user") return "Needs answer";
    if (toolName === "exit_plan_mode") return "Needs approval";
    return "Needs input";
}

function extractSummaryHint(toolArgs) {
    if (typeof toolArgs.summary !== "string") return "";
    for (const line of toolArgs.summary.split(/\r?\n/)) {
        const candidate = line.trim().replace(/^[-*]\s*/, "").trim();
        if (candidate) return normalizeBody(candidate);
    }
    return "";
}

function buildInteractionBody(toolName, toolArgs) {
    const question = typeof toolArgs.question === "string" ? normalizeBody(toolArgs.question) : "";
    if (toolName === "ask_user") return question || "Copilot needs your input.";

    const summaryHint = extractSummaryHint(toolArgs);
    if (toolName === "exit_plan_mode") {
        return summaryHint ? normalizeBody(`Plan is ready for approval: ${summaryHint}`) : "Plan is ready for your approval.";
    }

    if (question) return question;
    if (summaryHint) return normalizeBody(`Action needed: ${summaryHint}`);
    if (Array.isArray(toolArgs.actions) && toolArgs.actions.length > 0) return "Copilot is waiting for your action.";
    return "Copilot needs your input.";
}

async function isCmuxFrontmost() {
    const osascript = findExecutable("osascript");
    if (!osascript) return false;

    const expectedBundle = (process.env.CMUX_BUNDLE_ID || DEFAULT_CMUX_BUNDLE_ID).trim();
    if (!expectedBundle) return false;

    const script = 'tell application "System Events" to get bundle identifier of first process whose frontmost is true';
    const result = await runCommand(osascript, ["-e", script], { timeoutMs: 2000 });
    return result.ok && result.stdout.trim() === expectedBundle;
}

async function isCallerSurfaceFocused() {
    const result = await runCmux(["identify", "--json"], { timeoutMs: 2000 });
    if (!result.ok || !result.stdout.trim()) return false;

    let data;
    try {
        data = JSON.parse(result.stdout);
    } catch {
        return false;
    }

    const focused = data?.focused;
    const caller = data?.caller;
    return Boolean(
        focused?.surface_ref &&
            caller?.surface_ref &&
            focused.surface_ref === caller.surface_ref &&
            focused?.workspace_ref &&
            caller?.workspace_ref &&
            focused.workspace_ref === caller.workspace_ref,
    );
}

async function isSameCmuxSurfaceActive() {
    return Boolean(resolveCmuxBinary() && (await isCmuxFrontmost()) && (await isCallerSurfaceFocused()));
}

async function notify(title, subtitle, body) {
    state.lastNotification = { title, subtitle, body };

    const osascript = findExecutable("osascript");
    if (!osascript) return;

    let script = `display notification ${JSON.stringify(body)} with title ${JSON.stringify(title)}`;
    if (subtitle) script += ` subtitle ${JSON.stringify(subtitle)}`;
    const result = await runCommand(osascript, ["-e", script]);
    recordCommand("osascript display notification", result);
}

async function syncTitle(payload) {
    const title = buildWorkspaceTitle(payload);
    if (title && title !== state.title) {
        await updateWorkspaceTitle(title);
        state.title = title;
    }
}

async function handleSessionStart(input) {
    state.started = true;
    state.lastIntent = "";
    state.lastAttention = "";
    state.lastNotification = null;
    state.pendingInteraction = false;
    await clearLegacyStatuses();
    await clearCopilotStatus();
    await clearNotifications();
    await setCopilotStatus("Running", ["--color", "#34c759", "--icon", "bolt.fill"]);
    await syncTitle(input);
}

async function handleUserPromptSubmitted(input) {
    state.started = true;
    state.lastAttention = "";
    state.lastNotification = null;
    state.pendingInteraction = false;
    await clearLegacyStatuses();
    await clearCopilotStatus();
    await clearNotifications();
    await setCopilotStatus("Running", ["--color", "#34c759", "--icon", "bolt.fill"]);
}

async function handleReportIntent(input) {
    const toolArgs = parseToolArgs(input.toolArgs);
    const intent = typeof toolArgs.intent === "string" ? toolArgs.intent.trim() : "";
    if (!intent) return;

    if (!state.started) {
        await setCopilotStatus("Running", ["--color", "#34c759", "--icon", "bolt.fill"]);
        state.started = true;
    }

    await syncTitle(input);
    await clearLegacyStatuses();
    await clearNotifications();
    await setCopilotStatus(intent, ["--color", "#34c759", "--icon", "bolt.fill"]);
    state.lastAttention = "";
    state.lastNotification = null;
    state.pendingInteraction = false;
    state.lastIntent = intent;
}

async function handleInteractiveTool(input) {
    const toolName = input.toolName || "";
    const toolArgs = parseToolArgs(input.toolArgs);

    await clearLegacyStatuses();
    const attention = defaultInteractionSubtitle(toolName);
    await setCopilotStatus(attention, ["--icon", "bell.fill"]);
    state.lastAttention = attention;
    state.pendingInteraction = true;

    if (await isSameCmuxSurfaceActive()) return;

    const body = buildInteractionBody(toolName, toolArgs);
    const subtitle = buildContextSubtitle(input) || attention;
    await notify("Copilot CLI", subtitle, body);
}

async function handleNonInteractiveTool() {
    await clearLegacyStatuses();
    await clearNotifications();
    await setCopilotStatus("Running", ["--color", "#34c759", "--icon", "bolt.fill"]);
    state.lastAttention = "";
    state.lastNotification = null;
    state.pendingInteraction = false;
}

async function handleInteractiveToolComplete(input) {
    const toolName = input.toolName || "";
    const toolArgs = parseToolArgs(input.toolArgs);
    if (!isInteractiveToolUse(toolName, toolArgs)) return;

    state.pendingInteraction = false;
    state.lastAttention = "";
    state.lastNotification = null;
    await clearLegacyStatuses();
    await clearNotifications();
    await setCopilotStatus("Running", ["--color", "#34c759", "--icon", "bolt.fill"]);
}

async function handleSessionIdle() {
    await clearLegacyStatuses();
    if (!state.pendingInteraction) {
        await clearCopilotStatus();
        state.lastIntent = "";
    }
}

async function handleSessionEnd(input) {
    await clearLegacyStatuses();
    await clearCopilotStatus();
    await clearNotifications();

    const reason = String(input.reason || "unknown");
    state.started = false;
    state.lastIntent = "";
    state.lastAttention = "";
    state.lastNotification = null;
    state.pendingInteraction = false;

    if (await isSameCmuxSurfaceActive()) return;

    const body = reason === "complete" ? "Task finished." : `Task stopped (${reason}).`;
    const subtitle = buildContextSubtitle(input) || "Session ended";
    await notify("Copilot CLI", subtitle, body);
}

function rememberHandled(set, id) {
    if (!id) return false;
    if (set.has(id)) return true;
    set.add(id);
    if (set.size > 100) {
        const first = set.values().next().value;
        set.delete(first);
    }
    return false;
}

async function handleToolStart(input, toolCallId = "") {
    if (rememberHandled(handledToolStarts, toolCallId)) return;

    const toolName = input.toolName || "";
    const toolArgs = parseToolArgs(input.toolArgs);

    if (toolName === "report_intent") {
        await handleReportIntent(input);
        return;
    }

    if (isInteractiveToolUse(toolName, toolArgs)) {
        await handleInteractiveTool(input);
        return;
    }

    await handleNonInteractiveTool();
}

async function handleToolComplete(input, toolCallId = "") {
    if (rememberHandled(handledToolCompletes, toolCallId)) return;
    await handleInteractiveToolComplete(input);
}

async function safely(label, operation) {
    try {
        await operation();
    } catch (error) {
        state.lastError = `${label}: ${error instanceof Error ? error.message : String(error)}`;
    }
}

const session = await joinSession({
    tools: [
        {
            name: "cmux_status",
            description: "Inspect the copilot-cmux prototype extension state and cmux environment.",
            parameters: {
                type: "object",
                properties: {},
            },
            handler: async () => {
                const status = {
                    extension: "copilot-cmux-prototype",
                    cmuxBinary: resolveCmuxBinary() || null,
                    workspaceRef: getWorkspaceRef() || null,
                    state,
                };
                return JSON.stringify(status, null, 2);
            },
        },
    ],
    hooks: {
        onUserPromptSubmitted: async (input) => {
            await safely("onUserPromptSubmitted", () => handleUserPromptSubmitted(input));
        },
        onSessionStart: async (input) => {
            await safely("onSessionStart", () => handleSessionStart(input));
        },
        onPreToolUse: async (input) => {
            await safely("onPreToolUse", () => handleToolStart(input));
        },
        onPostToolUse: async (input) => {
            await safely("onPostToolUse", () => handleToolComplete(input));
        },
        onSessionEnd: async (input) => {
            await safely("onSessionEnd", () => handleSessionEnd(input));
        },
    },
});

session.on("tool.execution_start", async (event) => {
    await safely("tool.execution_start", () =>
        handleToolStart(
            {
                toolName: event.data?.toolName || "",
                toolArgs: event.data?.arguments || {},
                cwd: process.cwd(),
            },
            event.data?.toolCallId || "",
        ),
    );
});

session.on("tool.execution_complete", async (event) => {
    await safely("tool.execution_complete", () =>
        handleToolComplete(
            {
                toolName: event.data?.toolName || "",
                toolArgs: event.data?.arguments || {},
                toolResult: event.data?.result,
                cwd: process.cwd(),
            },
            event.data?.toolCallId || "",
        ),
    );
});

session.on("session.idle", async () => {
    await safely("session.idle", () => handleSessionIdle());
});

session.on("session.shutdown", async () => {
    await safely("session.shutdown", () => handleSessionEnd({ reason: "user_exit", cwd: process.cwd() }));
});
