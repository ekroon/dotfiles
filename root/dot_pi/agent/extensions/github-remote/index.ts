import type {
	ExtensionAPI,
	ExtensionCommandContext,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import os from "node:os";
import { basename, join } from "node:path";
import { promisify } from "node:util";

const CUSTOM_TYPE = "github-remote";
const STATUS_KEY = "github-remote";
const DEFAULT_MC_BASE_URL = "https://api.githubcopilot.com/agents";
const DEFAULT_FRONTEND_BASE_URL = "https://github.com";
const DEFAULT_INTEGRATION_ID = "copilot-developer-cli";
const HEARTBEAT_MS = 10_000;
const POLL_MS = 3_000;
const FLUSH_DEBOUNCE_MS = 250;
const MAX_PROCESSED_COMMAND_IDS = 200;
const MAX_TOOL_TEXT = 4_000;
const execFileAsync = promisify(execFile);

type NotifyType = "info" | "warning" | "error";

type TokenInfo = {
	token: string;
	source: string;
};

type RepoInfo = {
	owner: string;
	name: string;
	fullName: string;
	ownerId?: number;
	repoId?: number;
};

type PreviousRemote = {
	mcSessionId: string;
	mcTaskId: string;
	remoteUrl: string;
	agentTaskId: string;
	createdAt: string;
	movedAt: string;
	lastEventId?: string;
	reason?: string;
};

type RemoteState = {
	enabled: boolean;
	steeringEnabled?: boolean;
	mcSessionId: string;
	mcTaskId: string;
	remoteUrl: string;
	agentTaskId: string;
	piSessionId?: string;
	piSessionFile?: string;
	repo?: RepoInfo;
	createdAt: string;
	updatedAt: string;
	lastEventId?: string;
	remoteTitle?: string;
	processedCommandIds?: string[];
	previousRemotes?: PreviousRemote[];
	lastError?: string;
	tokenSource?: string;
};

type McEventSpec = {
	id?: string;
	parentId?: string | null;
	timestamp?: string;
	type: string;
	ephemeral?: boolean;
	data?: Record<string, unknown>;
};

type McEvent = McEventSpec & {
	id: string;
	parentId: string | null;
	timestamp: string;
};

type RemoteCommand = {
	id?: string;
	state?: string;
	type?: string;
	content?: unknown;
};

type ActiveAssistantMessage = {
	messageId: string;
	turnId?: string;
	text: string;
};

type ToolRequest = {
	toolCallId: string;
	name: string;
	arguments: Record<string, unknown>;
	type: "function";
	intentionSummary?: string;
};

type ActiveToolExecution = {
	toolCallId: string;
	toolName: string;
	arguments: Record<string, unknown>;
	turnId?: string;
	interactionId?: string;
	startedAt: number;
};

export default function githubRemoteExtension(pi: ExtensionAPI) {
	let state: RemoteState | undefined;
	let lastCtx: ExtensionContext | undefined;
	let tokenCache: TokenInfo | undefined;
	let heartbeatTimer: ReturnType<typeof setInterval> | undefined;
	let pollTimer: ReturnType<typeof setInterval> | undefined;
	let flushTimer: ReturnType<typeof setTimeout> | undefined;
	let uploadInFlight = false;
	let appendTail: Promise<void> = Promise.resolve();
	let heartbeatInFlight = false;
	let pollInFlight = false;
	let eventQueue: McEventSpec[] = [];
	let completedCommandIds = new Set<string>();
	let currentTurnId: string | undefined;
	let currentInteractionId: string | undefined;
	let activeAssistant: ActiveAssistantMessage | undefined;
	let activeTools = new Map<string, ActiveToolExecution>();
	let suppressUserMessageMirrors: string[] = [];
	let lastHeartbeatAt: string | undefined;
	let lastPollAt: string | undefined;

	function mcBaseUrl() {
		const base = (process.env.COPILOT_MC_BASE_URL || DEFAULT_MC_BASE_URL).replace(/\/+$/, "");
		const parsed = new URL(base);
		if (!parsed.hostname.endsWith("githubcopilot.com") && process.env.GITHUB_REMOTE_ALLOW_UNSAFE_BASE_URL !== "1") {
			throw new Error(`Refusing to send GitHub token to non-GitHub Copilot host: ${parsed.hostname}`);
		}
		return base;
	}

	function frontendBaseUrl() {
		return (process.env.COPILOT_MC_FRONTEND_URL || DEFAULT_FRONTEND_BASE_URL).replace(/\/+$/, "");
	}

	function integrationId() {
		return process.env.GITHUB_COPILOT_INTEGRATION_ID || DEFAULT_INTEGRATION_ID;
	}

	function notify(ctx: ExtensionContext | undefined, message: string, type: NotifyType = "info") {
		if (ctx?.hasUI) ctx.ui.notify(message, type);
		else console.log(`[github-remote] ${message}`);
	}

	function notifySoon(ctx: ExtensionContext | undefined, message: string, type: NotifyType = "info") {
		setTimeout(() => notify(ctx, message, type), 250);
	}

	function setStatus(ctx: ExtensionContext | undefined = lastCtx) {
		if (!ctx?.hasUI) return;
		if (!state?.enabled) {
			ctx.ui.setStatus(STATUS_KEY, "remote: off");
			return;
		}
		const running = isRunning();
		const shortTask = state.mcTaskId ? state.mcTaskId.slice(0, 8) : "unknown";
		const mode = isSteeringEnabled() ? "steer" : "view";
		ctx.ui.setStatus(STATUS_KEY, running ? `remote: ${mode} ${shortTask}` : "remote: off");
	}

	function isRunning() {
		return Boolean(heartbeatTimer);
	}

	function isSteeringEnabled() {
		return state?.steeringEnabled !== false;
	}

	function persist() {
		if (!state) return;
		state.updatedAt = new Date().toISOString();
		pi.appendEntry<RemoteState>(CUSTOM_TYPE, {
			...state,
			processedCommandIds: trimProcessedCommandIds(state.processedCommandIds ?? []),
		});
	}

	function restore(ctx: ExtensionContext) {
		lastCtx = ctx;
		state = undefined;
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "custom" && entry.customType === CUSTOM_TYPE && entry.data) {
				state = entry.data as RemoteState;
			}
		}
		if (state?.enabled && state.steeringEnabled === undefined) {
			state.steeringEnabled = true;
		}
		if (state?.processedCommandIds) {
			state.processedCommandIds = trimProcessedCommandIds(state.processedCommandIds);
		}
		setStatus(ctx);
	}

	function trimProcessedCommandIds(ids: string[]) {
		return ids.slice(Math.max(0, ids.length - MAX_PROCESSED_COMMAND_IDS));
	}

	function rememberProcessedCommandId(id: string) {
		if (!state) return;
		const ids = state.processedCommandIds ?? [];
		if (!ids.includes(id)) ids.push(id);
		state.processedCommandIds = trimProcessedCommandIds(ids);
	}

	function hasProcessedCommandId(id: string) {
		return Boolean(state?.processedCommandIds?.includes(id));
	}

	async function getGhCliToken(): Promise<TokenInfo | undefined> {
		try {
			const { stdout } = await execFileAsync("gh", ["auth", "token"], { timeout: 5_000, maxBuffer: 1024 * 1024 });
			const ghToken = String(stdout).trim();
			if (ghToken) return { token: ghToken, source: "gh auth token" };
		} catch {
			// gh may not be installed, logged in, or authorized. Fall through to Pi auth.
		}
		return undefined;
	}

	async function getToken(): Promise<TokenInfo> {
		for (const envName of ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"]) {
			const token = process.env[envName];
			if (token) return { token, source: envName };
		}

		// Prefer GitHub CLI auth for repo-attached sessions. Pi's github-copilot OAuth
		// refresh token can talk to Mission Control for repo-less sessions, but may not
		// be authorized for private org repos / SSO. `gh auth token` usually is.
		const ghToken = await getGhCliToken();
		if (ghToken) return ghToken;

		const authPath = join(process.env.PI_CODING_AGENT_DIR || join(os.homedir(), ".pi", "agent"), "auth.json");
		if (!existsSync(authPath)) throw new Error(`No env token, no gh auth token, and no Pi auth file at ${authPath}`);
		const auth = JSON.parse(await readFile(authPath, "utf8")) as Record<string, unknown>;
		const entry = auth["github-copilot"] as { type?: string; refresh?: string; access?: string } | undefined;
		if (!entry || entry.type !== "oauth") throw new Error("No github-copilot OAuth entry in Pi auth.json");
		if (entry.access) return { token: entry.access, source: "pi-auth:github-copilot.access" };
		if (entry.refresh) return { token: entry.refresh, source: "pi-auth:github-copilot.refresh" };
		throw new Error("github-copilot OAuth entry has no refresh/access token");
	}

	async function token() {
		if (!tokenCache) tokenCache = await getToken();
		return tokenCache;
	}

	function timeoutSignal(ms: number): AbortSignal {
		const timeout = (AbortSignal as unknown as { timeout?: (ms: number) => AbortSignal }).timeout;
		if (timeout) return timeout(ms);
		const controller = new AbortController();
		setTimeout(() => controller.abort(), ms).unref?.();
		return controller.signal;
	}

	function headers(tokenValue: string) {
		return {
			"Content-Type": "application/json",
			"Copilot-Integration-Id": integrationId(),
			Authorization: `Bearer ${tokenValue}`,
		};
	}

	async function mcRequest<T>(path: string, options: { method?: string; body?: unknown; tokenValue?: string; retried?: boolean } = {}): Promise<T> {
		const tokenInfo = options.tokenValue ? { token: options.tokenValue, source: "provided" } : await token();
		const method = options.method ?? "GET";
		const url = `${mcBaseUrl()}${path}`;
		const res = await fetch(url, {
			method,
			headers: headers(tokenInfo.token),
			body: options.body === undefined ? undefined : JSON.stringify(options.body),
			signal: timeoutSignal(15_000),
		});
		const text = await res.text();
		let json: unknown;
		try {
			json = text ? JSON.parse(text) : undefined;
		} catch {
			json = undefined;
		}
		if (!res.ok) {
			if (!options.tokenValue && !options.retried && (res.status === 401 || res.status === 403)) {
				tokenCache = undefined;
				return mcRequest<T>(path, { ...options, retried: true });
			}
			const details = json ? JSON.stringify(json) : text;
			throw new Error(`${method} ${url} -> ${res.status}${details ? `: ${details}` : ""}`);
		}
		return (json ?? text) as T;
	}

	async function githubRequest<T>(url: string, tokenValue: string): Promise<T> {
		const res = await fetch(url, {
			headers: {
				Authorization: `Bearer ${tokenValue}`,
				Accept: "application/vnd.github+json",
				"X-GitHub-Api-Version": "2022-11-28",
			},
			signal: timeoutSignal(15_000),
		});
		const text = await res.text();
		const json = text ? JSON.parse(text) : undefined;
		if (!res.ok) throw new Error(`GET GitHub repo metadata -> ${res.status}${text ? `: ${text}` : ""}`);
		return json as T;
	}

	async function detectRepo(ctx: ExtensionContext, tokenValue: string): Promise<RepoInfo | undefined> {
		const remote = await pi.exec("git", ["remote", "get-url", "origin"], { cwd: ctx.cwd, timeout: 5_000 });
		if (remote.code !== 0) return undefined;
		const parsed = parseGitHubRemote(remote.stdout.trim());
		if (!parsed) return undefined;

		try {
			const response = await githubRequest<{ id: number; owner: { id: number } }>(
				`https://api.github.com/repos/${encodeURIComponent(parsed.owner)}/${encodeURIComponent(parsed.name)}`,
				tokenValue,
			);
			return { ...parsed, ownerId: response.owner.id, repoId: response.id };
		} catch (error) {
			notify(ctx, `GitHub repo detected (${parsed.fullName}) but ID lookup failed; creating repo-less remote.`, "warning");
			state = state ? { ...state, lastError: errorMessage(error) } : state;
			return parsed;
		}
	}

	function parseGitHubRemote(remote: string): RepoInfo | undefined {
		let owner: string | undefined;
		let name: string | undefined;

		let match = remote.match(/^git@github\.com:([^/]+)\/(.+?)(?:\.git)?$/);
		if (match) {
			owner = match[1];
			name = match[2];
		} else {
			match = remote.match(/^ssh:\/\/git@github\.com\/([^/]+)\/(.+?)(?:\.git)?$/);
			if (match) {
				owner = match[1];
				name = match[2];
			} else {
				try {
					const url = new URL(remote);
					if (url.hostname !== "github.com") return undefined;
					const parts = url.pathname.replace(/^\/+/, "").split("/");
					owner = parts[0];
					name = parts[1];
				} catch {
					return undefined;
				}
			}
		}

		if (!owner || !name) return undefined;
		name = name.replace(/\.git$/, "").replace(/\/+$/, "");
		if (!owner || !name) return undefined;
		return { owner, name, fullName: `${owner}/${name}` };
	}

	function advancesDurableParent(spec: McEventSpec) {
		// Mission Control may omit streaming/ephemeral events from durable /events or
		// logs reconstruction. Keep durable events parented to the last durable event.
		return spec.ephemeral !== true && spec.type !== "assistant.message_delta";
	}

	function createEventChain(specs: McEventSpec[], initialParentId: string | undefined): { events: McEvent[]; lastEventId?: string } {
		let parentId: string | null = initialParentId ?? null;
		let lastEventId = initialParentId;
		const events = specs.map((spec) => {
			const id = spec.id || randomUUID();
			const event: McEvent = {
				id,
				parentId,
				timestamp: spec.timestamp || new Date().toISOString(),
				...spec,
			};
			if (advancesDurableParent(spec)) {
				parentId = id;
				lastEventId = id;
			}
			return event;
		});
		return { events, lastEventId };
	}

	async function appendEventsNow(specs: McEventSpec[], commandIds: string[] = []) {
		const run = async () => {
			const targetState = state;
			if (!targetState) throw new Error("GitHub remote is not initialized");
			const targetSessionId = targetState.mcSessionId;
			const { events, lastEventId } = createEventChain(specs, targetState.lastEventId);
			const body = {
				events,
				completed_command_ids: commandIds,
			};
			await mcRequest(`/sessions/${encodeURIComponent(targetSessionId)}/events`, { method: "POST", body });
			if (state !== targetState || state?.mcSessionId !== targetSessionId) return events;
			state.lastEventId = lastEventId;
			state.lastError = undefined;
			if (events.length > 0 || commandIds.length > 0) persist();
			return events;
		};

		const previous = appendTail;
		let release: () => void = () => {};
		appendTail = new Promise<void>((resolve) => {
			release = resolve;
		});
		await previous.catch(() => {});
		try {
			return await run();
		} finally {
			release();
		}
	}

	function enqueueEvent(spec: McEventSpec | McEventSpec[]) {
		if (!state?.enabled) return;
		const specs = Array.isArray(spec) ? spec : [spec];
		if (specs.length === 0) return;
		eventQueue.push(...specs);
		scheduleFlush();
	}

	function scheduleFlush(delay = FLUSH_DEBOUNCE_MS) {
		if (flushTimer) clearTimeout(flushTimer);
		flushTimer = setTimeout(() => {
			flushTimer = undefined;
			void flushQueued();
		}, delay);
	}

	async function flushQueued() {
		if (!state?.mcSessionId || uploadInFlight) return;
		if (eventQueue.length === 0 && completedCommandIds.size === 0) return;

		uploadInFlight = true;
		const specs = eventQueue;
		const commandIds = [...completedCommandIds];
		eventQueue = [];
		completedCommandIds = new Set<string>();
		try {
			await appendEventsNow(specs, commandIds);
		} catch (error) {
			eventQueue = [...specs, ...eventQueue];
			for (const id of commandIds) completedCommandIds.add(id);
			setLastError(error);
		} finally {
			uploadInFlight = false;
			if (eventQueue.length > 0 || completedCommandIds.size > 0) scheduleFlush(1_000);
		}
	}

	function ackCommand(id: string) {
		completedCommandIds.add(id);
		scheduleFlush(0);
	}

	function sleep(ms: number) {
		return new Promise((resolve) => setTimeout(resolve, ms));
	}

	async function drainUploads() {
		while (uploadInFlight) await sleep(50);
		await flushQueued();
		while (uploadInFlight) await sleep(50);
	}

	async function heartbeatOnce() {
		if (!state?.enabled || !state.mcSessionId || heartbeatInFlight) return;
		heartbeatInFlight = true;
		const targetState = state;
		const targetSessionId = state.mcSessionId;
		try {
			await syncRemoteTitleFromPi();
			if (eventQueue.length > 0 || completedCommandIds.size > 0) {
				await flushQueued();
				return;
			}
			await mcRequest(`/sessions/${encodeURIComponent(targetSessionId)}/events`, {
				method: "POST",
				body: { events: [] },
			});
			if (state !== targetState || state?.mcSessionId !== targetSessionId) return;
			lastHeartbeatAt = new Date().toISOString();
			state.lastError = undefined;
		} catch (error) {
			setLastError(error);
		} finally {
			heartbeatInFlight = false;
		}
	}

	async function pollOnce() {
		if (!state?.enabled || !state.mcSessionId || !isSteeringEnabled() || pollInFlight) return;
		pollInFlight = true;
		const targetState = state;
		const targetSessionId = state.mcSessionId;
		try {
			const response = await mcRequest<{ commands?: RemoteCommand[] } | RemoteCommand[]>(
				`/sessions/${encodeURIComponent(targetSessionId)}/commands`,
			);
			if (state !== targetState || state?.mcSessionId !== targetSessionId) return;
			lastPollAt = new Date().toISOString();
			const commands = Array.isArray(response) ? response : response.commands ?? [];
			for (const command of commands) await handleRemoteCommand(command);
		} catch (error) {
			setLastError(error);
		} finally {
			pollInFlight = false;
		}
	}

	async function handleRemoteCommand(command: RemoteCommand) {
		if (!state || !isSteeringEnabled() || command.state !== "in_progress" || !command.id) return;

		if (hasProcessedCommandId(command.id)) {
			ackCommand(command.id);
			return;
		}

		const type = command.type || "user_message";
		try {
			if (type === "user_message") {
				const content = String(command.content ?? "").trim();
				if (content) {
					const ctx = lastCtx;
					// Correlate the remote UI command with the user.message event we publish.
					// Without this, GitHub can keep the optimistic "queued for Copilot" row
					// even though /commands marks the command completed.
					suppressUserMessageMirrors.push(content);
					enqueueEvent({ type: "user.message", data: { content, source: `command-${command.id}` } });
					if (ctx?.isIdle()) pi.sendUserMessage(content);
					else pi.sendUserMessage(content, { deliverAs: "steer" });
					notify(ctx, "GitHub remote message delivered to Pi.", "info");
				}
			} else if (type === "abort") {
				lastCtx?.abort();
				notify(lastCtx, "GitHub remote requested abort.", "warning");
			} else {
				notify(lastCtx, `Ignoring unsupported GitHub remote command type: ${type}`, "warning");
				return;
			}
			rememberProcessedCommandId(command.id);
			persist();
			ackCommand(command.id);
		} catch (error) {
			setLastError(error);
			notify(lastCtx, `GitHub remote command failed: ${errorMessage(error)}`, "error");
		}
	}

	function startLoops(ctx: ExtensionContext | undefined = lastCtx) {
		if (!state?.enabled || !state.mcSessionId) return;
		lastCtx = ctx;
		if (!heartbeatTimer) {
			heartbeatTimer = setInterval(() => void heartbeatOnce(), HEARTBEAT_MS);
			void heartbeatOnce();
		}
		if (isSteeringEnabled()) {
			if (!pollTimer) {
				pollTimer = setInterval(() => void pollOnce(), POLL_MS);
				void pollOnce();
			}
		} else if (pollTimer) {
			clearInterval(pollTimer);
			pollTimer = undefined;
		}
		setStatus(ctx);
	}

	function stopLoops() {
		if (heartbeatTimer) clearInterval(heartbeatTimer);
		if (pollTimer) clearInterval(pollTimer);
		if (flushTimer) clearTimeout(flushTimer);
		heartbeatTimer = undefined;
		pollTimer = undefined;
		flushTimer = undefined;
		setStatus();
	}

	function setLastError(error: unknown) {
		if (!state) return;
		state.lastError = errorMessage(error);
		setStatus();
	}

	function errorMessage(error: unknown) {
		return error instanceof Error ? error.message : String(error);
	}

	function getExplicitPiSessionName(ctx: ExtensionContext) {
		const explicitName = pi.getSessionName?.() || ctx.sessionManager.getSessionName?.();
		return explicitName?.trim() || undefined;
	}

	function getPiSessionTitle(ctx: ExtensionContext, mcTaskId: string) {
		const explicitName = getExplicitPiSessionName(ctx);
		if (explicitName) return explicitName;

		const firstUserMessage = ctx.sessionManager
			.getBranch()
			.find((entry) => entry.type === "message" && entry.message.role === "user");
		if (firstUserMessage?.type === "message" && firstUserMessage.message.role === "user") {
			const text = textFromContent(firstUserMessage.message.content).replace(/\s+/g, " ").trim();
			if (text) return text.length > 80 ? `${text.slice(0, 77)}…` : text;
		}

		const cwdName = basename(ctx.cwd);
		return cwdName || `Pi session ${mcTaskId.slice(0, 8)}`;
	}

	function initialEvents(
		ctx: ExtensionContext,
		repo: RepoInfo | undefined,
		agentTaskId: string,
		mcTaskId: string,
		remoteSteerable: boolean,
	): McEventSpec[] {
		const now = new Date().toISOString();
		const repository = repo?.fullName;
		const title = getPiSessionTitle(ctx, mcTaskId);
		return [
			{
				type: "session.start",
				data: {
					version: 1,
					sessionId: agentTaskId,
					producer: "pi-github-remote",
					copilotVersion: "pi-native-github-remote",
					startTime: now,
					remoteSteerable,
					context: {
						cwd: ctx.cwd,
						repository,
						hostType: repository ? "github" : undefined,
					},
				},
			},
			{ type: "session.remote_steerable_changed", data: { remoteSteerable } },
			{
				type: "session.title_changed",
				data: { title },
			},
			{ type: "session.idle", ephemeral: true, data: {} },
		];
	}

	function previousRemoteSnapshot(remote: RemoteState, reason: string): PreviousRemote {
		return {
			mcSessionId: remote.mcSessionId,
			mcTaskId: remote.mcTaskId,
			remoteUrl: remote.remoteUrl,
			agentTaskId: remote.agentTaskId,
			createdAt: remote.createdAt,
			movedAt: new Date().toISOString(),
			lastEventId: remote.lastEventId,
			reason,
		};
	}

	function trimPreviousRemotes(remotes: PreviousRemote[]) {
		return remotes.slice(Math.max(0, remotes.length - 10));
	}

	async function createRemoteSession(
		ctx: ExtensionContext,
		options: {
			forceNewAgentTaskId?: boolean;
			previousRemotes?: PreviousRemote[];
			steeringEnabled?: boolean;
			requireRepo?: boolean;
			notifyUser?: boolean;
		} = {},
	) {
		const tokenInfo = await token();
		const repo = await detectRepo(ctx, tokenInfo.token);
		if (options.requireRepo && !repo) return false;

		const steeringEnabled = options.steeringEnabled ?? true;
		const piSessionId = ctx.sessionManager.getSessionId?.() || randomUUID();
		const agentTaskId = options.forceNewAgentTaskId ? `pi-${piSessionId}-${randomUUID()}` : piSessionId || `pi-${randomUUID()}`;
		const body: Record<string, unknown> = {
			agent_task_id: agentTaskId,
			indexing_level: "user",
		};
		if (repo?.ownerId && repo.repoId) {
			body.owner_id = repo.ownerId;
			body.repo_id = repo.repoId;
		}

		if (options.notifyUser !== false) {
			notify(ctx, `Creating GitHub remote session${repo?.fullName ? ` for ${repo.fullName}` : ""}...`, "info");
		}
		const response = await mcRequest<{ id?: string; task_id?: string }>("/sessions", {
			method: "POST",
			body,
			tokenValue: tokenInfo.token,
		});
		if (!response.id || !response.task_id) throw new Error(`Unexpected Mission Control create response: ${JSON.stringify(response)}`);

		const remoteUrl = repo
			? `${frontendBaseUrl()}/${repo.owner}/${repo.name}/tasks/${response.task_id}`
			: `${frontendBaseUrl()}/copilot/tasks/${response.task_id}`;

		state = {
			enabled: false,
			steeringEnabled,
			mcSessionId: response.id,
			mcTaskId: response.task_id,
			remoteUrl,
			agentTaskId,
			piSessionId,
			piSessionFile: ctx.sessionManager.getSessionFile(),
			repo,
			createdAt: new Date().toISOString(),
			updatedAt: new Date().toISOString(),
			remoteTitle: getPiSessionTitle(ctx, response.task_id),
			processedCommandIds: [],
			previousRemotes: trimPreviousRemotes(options.previousRemotes ?? []),
			tokenSource: tokenInfo.source,
		};
		await appendEventsNow(initialEvents(ctx, repo, agentTaskId, response.task_id, steeringEnabled));
		state.enabled = true;
		persist();
		startLoops(ctx);
		if (options.notifyUser !== false) {
			notify(ctx, `GitHub remote ${steeringEnabled ? "steering enabled" : "session created"}. Link: ${state.remoteUrl}`, "info");
		}
		return true;
	}

	async function updateRemoteTitle(ctx: ExtensionCommandContext | ExtensionContext, explicitTitle?: string, options: { notifyUser?: boolean } = { notifyUser: true }) {
		lastCtx = ctx;
		if (!state?.mcSessionId) {
			notify(ctx, "GitHub remote title is not available. Run /remote on first.", "warning");
			return;
		}
		const title = explicitTitle?.trim() || getPiSessionTitle(ctx, state.mcTaskId);
		state.remoteTitle = title;
		await appendEventsNow([{ type: "session.title_changed", data: { title } }]);
		if (options.notifyUser !== false) notify(ctx, `GitHub remote title sent: ${title}`, "info");
	}

	async function syncRemoteTitleFromPi() {
		if (!state?.enabled || !state.mcSessionId || !lastCtx) return;
		const explicitName = getExplicitPiSessionName(lastCtx);
		if (!explicitName || state.remoteTitle === explicitName) return;
		try {
			await drainUploads();
			await updateRemoteTitle(lastCtx, explicitName, { notifyUser: false });
		} catch (error) {
			setLastError(error);
		}
	}

	async function enableSteering(ctx: ExtensionCommandContext | ExtensionContext) {
		lastCtx = ctx;
		if (!state?.enabled || !state.mcSessionId) {
			await createRemoteSession(ctx, { previousRemotes: state?.previousRemotes, steeringEnabled: true });
			return;
		}

		await updateRemoteTitle(ctx);
		if (state.steeringEnabled !== true) {
			await appendEventsNow([{ type: "session.remote_steerable_changed", data: { remoteSteerable: true } }]);
			state.steeringEnabled = true;
			persist();
			startLoops(ctx);
			notify(ctx, `GitHub remote steering enabled: ${state.remoteUrl}`, "info");
			return;
		}

		startLoops(ctx);
		notify(ctx, `GitHub remote steering already enabled: ${state.remoteUrl}`, "info");
	}

	async function enable(ctx: ExtensionCommandContext) {
		await enableSteering(ctx);
	}

	async function ensureAutoRemoteSession(ctx: ExtensionContext) {
		if (state?.enabled && state.mcSessionId) return;
		try {
			await createRemoteSession(ctx, {
				previousRemotes: state?.previousRemotes,
				steeringEnabled: false,
				requireRepo: true,
			});
		} catch (error) {
			console.log(`[github-remote] auto remote session skipped: ${errorMessage(error)}`);
		}
	}

	function shutdownData(reason: string) {
		return {
			shutdownType: "routine",
			reason,
			totalPremiumRequests: 0,
			totalApiDurationMs: 0,
			sessionStartTime: state?.createdAt ? Date.parse(state.createdAt) : Date.now(),
			codeChanges: { linesAdded: 0, linesRemoved: 0, filesModified: [] },
			modelMetrics: {},
		};
	}

	async function rotateRemoteSession(ctx: ExtensionContext, reason: string, notice?: string) {
		lastCtx = ctx;
		const oldState = state;
		let previousRemotes = oldState?.previousRemotes ?? [];

		if (oldState?.mcSessionId) {
			notify(ctx, `Moving GitHub remote session. Old URL: ${oldState.remoteUrl}`, "info");
			try {
				await drainUploads();
				await appendEventsNow([
					{ type: "session.remote_steerable_changed", data: { remoteSteerable: false } },
					{ type: "session.shutdown", data: shutdownData(reason) },
				]);
			} catch (error) {
				setLastError(error);
				notify(ctx, `Old GitHub remote shutdown event failed: ${errorMessage(error)}`, "warning");
			}
			previousRemotes = trimPreviousRemotes([...previousRemotes, previousRemoteSnapshot(oldState, reason)]);
		}

		stopLoops();
		eventQueue = [];
		completedCommandIds = new Set<string>();
		activeAssistant = undefined;
		activeTools = new Map<string, ActiveToolExecution>();
		suppressUserMessageMirrors = [];
		currentTurnId = undefined;
		currentInteractionId = undefined;
		if (oldState) {
			state = { ...oldState, enabled: false, previousRemotes };
			persist();
		}
		await createRemoteSession(ctx, {
			forceNewAgentTaskId: true,
			previousRemotes,
			steeringEnabled: oldState?.steeringEnabled ?? true,
		});
		if (notice) {
			await appendEventsNow([{ type: "system.message", data: { role: "system", content: notice } }]);
		}
	}

	async function moveToNewRemote(ctx: ExtensionCommandContext) {
		await rotateRemoteSession(ctx, "moved_to_new_remote");
	}

	async function disableSteering(ctx: ExtensionCommandContext | ExtensionContext) {
		lastCtx = ctx;
		if (!state?.enabled || !state.mcSessionId) {
			notify(ctx, "GitHub remote session is not active.", "warning");
			return;
		}
		if (state.steeringEnabled === false) {
			notify(ctx, "GitHub remote steering is already disabled.", "info");
			return;
		}

		try {
			await drainUploads();
			await appendEventsNow([{ type: "session.remote_steerable_changed", data: { remoteSteerable: false } }]);
		} catch (error) {
			setLastError(error);
			notify(ctx, `Failed to disable GitHub remote steering: ${errorMessage(error)}`, "warning");
		}

		state.steeringEnabled = false;
		persist();
		startLoops(ctx);
		notify(ctx, "GitHub remote steering disabled.", "info");
	}

	async function shutdownRemoteSession(ctx: ExtensionCommandContext | ExtensionContext, reason = "manual") {
		lastCtx = ctx;
		if (!state?.mcSessionId) {
			notify(ctx, "GitHub remote is not enabled.", "warning");
			return;
		}

		try {
			await drainUploads();
			await appendEventsNow([
				{ type: "session.remote_steerable_changed", data: { remoteSteerable: false } },
				{ type: "session.shutdown", data: shutdownData(reason) },
			]);
		} catch (error) {
			setLastError(error);
			notify(ctx, `Failed to send GitHub remote shutdown event: ${errorMessage(error)}`, "warning");
		}

		state.enabled = false;
		state.steeringEnabled = false;
		persist();
		stopLoops();
		notify(ctx, "GitHub remote disabled.", "info");
	}

	function statusText() {
		if (!state) return "GitHub remote: disabled (no session)";
		return [
			`GitHub remote session: ${state.enabled ? "active" : "inactive"}`,
			`Steering: ${state.enabled && isSteeringEnabled() ? "enabled" : "disabled"}`,
			`URL: ${state.remoteUrl}`,
			`mcSessionId: ${state.mcSessionId}`,
			`mcTaskId: ${state.mcTaskId}`,
			`lastEventId: ${state.lastEventId ?? "<none>"}`,
			`heartbeat: ${heartbeatTimer ? "running" : "stopped"}${lastHeartbeatAt ? ` (last ${lastHeartbeatAt})` : ""}`,
			`poller: ${pollTimer ? "running" : "stopped"}${lastPollAt ? ` (last ${lastPollAt})` : ""}`,
			`repo: ${state.repo?.fullName ?? "<repo-less>"}${state.repo?.repoId ? ` (${state.repo.ownerId}/${state.repo.repoId})` : ""}`,
			`remoteTitle: ${state.remoteTitle ?? "<unknown>"}`,
			`tokenSource: ${state.tokenSource ?? tokenCache?.source ?? "<unknown>"}`,
			state.previousRemotes?.length ? `previousRemotes: ${state.previousRemotes.length} (last ${state.previousRemotes.at(-1)?.remoteUrl})` : undefined,
			state.lastError ? `lastError: ${state.lastError}` : undefined,
		]
			.filter(Boolean)
			.join("\n");
	}

	function showStatus(ctx: ExtensionContext) {
		lastCtx = ctx;
		setStatus(ctx);
		notify(ctx, statusText(), state?.lastError ? "warning" : "info");
	}

	function showUrl(ctx: ExtensionContext) {
		lastCtx = ctx;
		if (!state?.remoteUrl) {
			notify(ctx, "GitHub remote URL is not available. Run /remote on first.", "warning");
			return;
		}
		notify(ctx, state.remoteUrl, "info");
	}

	function textFromContent(content: unknown): string {
		if (typeof content === "string") return content;
		if (!Array.isArray(content)) return "";
		return content
			.map((block) => {
				if (!block || typeof block !== "object") return "";
				const typed = block as { type?: string; text?: string; thinking?: string };
				if (typed.type === "text") return typed.text ?? "";
				return "";
			})
			.join("");
	}

	function asRecord(value: unknown): Record<string, unknown> {
		return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
	}

	function compactText(value: unknown, max = MAX_TOOL_TEXT) {
		let text: string;
		try {
			text = typeof value === "string" ? value : JSON.stringify(value);
		} catch {
			text = String(value);
		}
		if (text.length <= max) return text;
		return `${text.slice(0, max)}… [truncated ${text.length - max} chars]`;
	}

	function extractToolRequests(content: unknown): ToolRequest[] {
		if (!Array.isArray(content)) return [];
		const requests: ToolRequest[] = [];
		for (const block of content) {
			if (!block || typeof block !== "object") continue;
			const toolCall = block as { type?: string; id?: string; name?: string; arguments?: unknown };
			if (toolCall.type !== "toolCall" || !toolCall.id || !toolCall.name) continue;
			requests.push({
				toolCallId: toolCall.id,
				name: toolCall.name,
				arguments: asRecord(toolCall.arguments),
				type: "function",
				intentionSummary: toolCall.name,
			});
		}
		return requests;
	}

	function toolResultText(result: unknown) {
		const record = asRecord(result);
		const content = record.content;
		if (Array.isArray(content)) {
			const text = textFromContent(content);
			if (text) return compactText(text);
		}
		if (typeof content === "string") return compactText(content);
		return compactText(result);
	}

	function modelName(ctx: ExtensionContext | undefined) {
		return ctx?.model?.id ?? "";
	}

	pi.on("session_start", async (_event, ctx) => {
		restore(ctx);
		if (state?.enabled && state.mcSessionId) {
			startLoops(ctx);
			notifySoon(ctx, `GitHub remote connected. Link: ${state.remoteUrl}`, "info");
			return;
		}
		await ensureAutoRemoteSession(ctx);
		if (state?.enabled && state.mcSessionId) {
			notifySoon(ctx, `GitHub remote connected. Link: ${state.remoteUrl}`, "info");
		}
	});

	pi.on("session_tree", async (event, ctx) => {
		if (!state?.enabled || !state.mcSessionId) {
			restore(ctx);
			return;
		}
		try {
			await rotateRemoteSession(
				ctx,
				"tree_navigation",
				"Pi navigated to a different conversation tree branch. This GitHub remote session starts fresh for the selected branch; earlier context remains available in Pi.",
			);
		} catch (error) {
			setLastError(error);
			notify(ctx, `Failed to create GitHub remote for tree branch: ${errorMessage(error)}`, "error");
		}
	});

	pi.on("session_shutdown", async (event, ctx) => {
		lastCtx = ctx;
		const shouldMarkOffline = state?.enabled && event.reason !== "reload";
		if (state?.enabled) await drainUploads();
		stopLoops();
		if (shouldMarkOffline) await shutdownRemoteSession(ctx, event.reason);
	});

	pi.on("message_end", async (event) => {
		if (!state?.enabled) return;
		if (event.message.role === "user") {
			const content = textFromContent(event.message.content).trim();
			const suppressIndex = suppressUserMessageMirrors.indexOf(content);
			if (suppressIndex >= 0) {
				suppressUserMessageMirrors.splice(suppressIndex, 1);
			} else if (content) {
				enqueueEvent({ type: "user.message", data: { content } });
			}
		} else if (event.message.role === "assistant") {
			const content = textFromContent(event.message.content);
			const toolRequests = extractToolRequests(event.message.content);
			if (!content.trim() && toolRequests.length === 0) {
				activeAssistant = undefined;
				return;
			}

			const messageId = activeAssistant?.messageId ?? randomUUID();
			if (!activeAssistant && content.trim()) {
				enqueueEvent({ type: "assistant.message_start", ephemeral: true, data: { messageId } });
			}

			const data: Record<string, unknown> = {
				messageId,
				turnId: activeAssistant?.turnId ?? currentTurnId,
				content,
			};
			if (toolRequests.length > 0) data.toolRequests = toolRequests;
			if (currentInteractionId) data.interactionId = currentInteractionId;
			enqueueEvent({ type: "assistant.message", data });
			activeAssistant = undefined;
		}
	});

	pi.on("message_start", async (_event) => {
		// Do not emit assistant.message_start here. Tool-only assistant messages often
		// have no visible text; emitting empty assistant messages appears to confuse
		// GitHub task rendering. Start text messages lazily on first delta/final text.
	});

	pi.on("message_update", async (event) => {
		if (!state?.enabled || event.message.role !== "assistant") return;
		if (!activeAssistant) {
			activeAssistant = { messageId: randomUUID(), turnId: currentTurnId, text: "" };
			enqueueEvent({ type: "assistant.message_start", ephemeral: true, data: { messageId: activeAssistant.messageId } });
		}
		let delta = "";
		if (event.assistantMessageEvent.type === "text_delta") {
			delta = event.assistantMessageEvent.delta;
		} else {
			const next = textFromContent(event.message.content);
			if (next.startsWith(activeAssistant.text)) delta = next.slice(activeAssistant.text.length);
		}
		if (!delta) return;
		activeAssistant.text += delta;
		enqueueEvent({
			type: "assistant.message_delta",
			ephemeral: true,
			data: { messageId: activeAssistant.messageId, deltaContent: delta },
		});
	});

	pi.on("agent_start", async () => {
		if (!state?.enabled) return;
		currentInteractionId = randomUUID();
	});

	pi.on("turn_start", async () => {
		if (!state?.enabled) return;
		currentTurnId = randomUUID();
		enqueueEvent({ type: "assistant.turn_start", data: { turnId: currentTurnId, interactionId: currentInteractionId } });
	});

	pi.on("turn_end", async () => {
		if (!state?.enabled || !currentTurnId) return;
		enqueueEvent({ type: "assistant.turn_end", data: { turnId: currentTurnId, interactionId: currentInteractionId } });
		currentTurnId = undefined;
	});

	pi.on("agent_end", async () => {
		if (!state?.enabled) return;
		enqueueEvent({ type: "session.idle", ephemeral: true, data: {} });
		currentInteractionId = undefined;
	});

	pi.on("tool_execution_start", async (event) => {
		if (!state?.enabled) return;
		const execution: ActiveToolExecution = {
			toolCallId: event.toolCallId,
			toolName: event.toolName,
			arguments: asRecord(event.args),
			turnId: currentTurnId,
			interactionId: currentInteractionId,
			startedAt: Date.now(),
		};
		activeTools.set(event.toolCallId, execution);
		enqueueEvent({
			type: "tool.execution_start",
			data: {
				toolCallId: event.toolCallId,
				toolName: event.toolName,
				arguments: execution.arguments,
				turnId: currentTurnId,
			},
		});
	});

	pi.on("tool_execution_end", async (event, ctx) => {
		if (!state?.enabled) return;
		const execution = activeTools.get(event.toolCallId) ?? {
			toolCallId: event.toolCallId,
			toolName: event.toolName,
			arguments: {},
			turnId: currentTurnId,
			interactionId: currentInteractionId,
			startedAt: Date.now(),
		};
		activeTools.delete(event.toolCallId);

		const resultText = toolResultText(event.result);
		const hookInvocationId = randomUUID();
		const toolTelemetry = asRecord(asRecord(event.result).details).toolTelemetry ?? {};
		enqueueEvent([
			{
				type: "hook.start",
				data: {
					hookInvocationId,
					hookType: "postToolUse",
					input: {
						sessionId: state.agentTaskId,
						timestamp: Date.now(),
						cwd: ctx.cwd,
						toolName: event.toolName,
						toolArgs: execution.arguments,
						toolResult: {
							textResultForLlm: resultText,
							resultType: event.isError ? "error" : "success",
							toolTelemetry,
						},
					},
				},
			},
			{ type: "hook.end", data: { hookInvocationId, hookType: "postToolUse", success: !event.isError } },
			{
				type: "tool.execution_complete",
				data: {
					toolCallId: event.toolCallId,
					model: modelName(ctx),
					interactionId: execution.interactionId,
					turnId: execution.turnId,
					success: !event.isError,
					result: { content: resultText, detailedContent: resultText },
					toolTelemetry,
				},
			},
		]);
	});

	pi.registerCommand("remote", {
		description: "Manage GitHub.com Copilot remote session/steering for this Pi session (on/off/new/title/status/url/shutdown)",
		getArgumentCompletions(prefix) {
			const commands = ["on", "off", "new", "recreate", "move", "title", "status", "url", "shutdown"];
			return commands
				.filter((value) => value.startsWith(prefix.trim()))
				.map((value) => ({ value, label: value }));
		},
		handler: async (args, ctx) => {
			lastCtx = ctx;
			const parts = args.trim().split(/\s+/);
			const subcommand = parts[0] || "status";
			try {
				if (subcommand === "on") await enable(ctx);
				else if (subcommand === "off") await disableSteering(ctx);
				else if (subcommand === "new" || subcommand === "recreate" || subcommand === "move") await moveToNewRemote(ctx);
				else if (subcommand === "title") await updateRemoteTitle(ctx, args.trim().slice(subcommand.length));
				else if (subcommand === "status") showStatus(ctx);
				else if (subcommand === "url") showUrl(ctx);
				else if (subcommand === "shutdown") await shutdownRemoteSession(ctx);
				else notify(ctx, "Usage: /remote on|off|new|title|status|url|shutdown", "warning");
			} catch (error) {
				setLastError(error);
				notify(ctx, `GitHub remote error: ${errorMessage(error)}`, "error");
			}
		},
	});
}
