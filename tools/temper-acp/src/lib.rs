use anyhow::{Context, Result};
use regex::Regex;
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::process::Command;

const SUCCESSOR_METHOD: &str = "_proxy/successor";
const MAX_AUTOMATIC_FOLLOWUPS: usize = 3;

#[derive(Clone, Debug, Default, Deserialize)]
struct Frontmatter {
    #[serde(default)]
    name: String,
    #[serde(default)]
    once: bool,
    #[serde(default)]
    triggers: Vec<Trigger>,
}

#[derive(Clone, Debug, Deserialize)]
struct Trigger {
    event: String,
    tool: Option<String>,
    command: Option<String>,
    when: Option<String>,
    action: Option<String>,
    worktree: Option<bool>,
}

#[derive(Clone, Debug)]
struct Skill {
    name: String,
    once: bool,
    triggers: Vec<Trigger>,
    content: String,
}

#[derive(Clone, Debug, Default)]
struct ToolCall {
    kind: String,
    title: String,
    raw_input: Value,
    locations: Vec<PathBuf>,
    before_dispatched: bool,
}

#[derive(Debug, Default)]
struct Session {
    cwd: PathBuf,
    active: bool,
    cancelled: bool,
    fired_once: HashSet<String>,
    queued: Vec<(String, String)>,
    tools: HashMap<String, ToolCall>,
    followups: usize,
}

enum Pending {
    Client {
        id: Value,
        method: String,
        cwd: Option<PathBuf>,
        session_id: Option<String>,
    },
    Agent {
        id: Value,
    },
    Automatic {
        session_id: String,
    },
}

#[derive(Clone)]
struct Event {
    name: &'static str,
    tool: String,
    command: String,
    paths: Vec<PathBuf>,
}

pub struct Proxy {
    roots: Vec<PathBuf>,
    pending: HashMap<String, Pending>,
    sessions: HashMap<String, Session>,
    next_id: u64,
}

impl Proxy {
    pub fn new(roots: Vec<PathBuf>) -> Self {
        Self {
            roots,
            pending: HashMap::new(),
            sessions: HashMap::new(),
            next_id: 1,
        }
    }

    pub async fn handle(&mut self, message: Value) -> Result<Vec<Value>> {
        if message.get("method").is_some() {
            if message.get("method").and_then(Value::as_str) == Some(SUCCESSOR_METHOD) {
                return self.handle_successor_message(message).await;
            }
            return self.handle_client_message(message).await;
        }
        self.response(message).await
    }

    async fn handle_client_message(&mut self, mut message: Value) -> Result<Vec<Value>> {
        let method = message["method"].as_str().unwrap_or_default().to_owned();
        let params = message.get("params").cloned().unwrap_or(Value::Null);
        if method == "session/cancel"
            && let Some(session_id) = session_id(&params)
            && let Some(session) = self.sessions.get_mut(session_id)
        {
            session.queued.clear();
            session.followups = 0;
            session.cancelled = true;
        }

        let id = message.get("id").cloned();
        if id.is_none() {
            message["method"] = Value::String(SUCCESSOR_METHOD.into());
            message["params"] = successor_params(&method, params);
            return Ok(vec![message]);
        }

        let session = session_id(&params).map(str::to_owned);
        if method == "session/prompt" {
            self.begin_prompt(&params).await?;
        }
        let cwd = matches!(
            method.as_str(),
            "session/new" | "session/load" | "session/resume"
        )
        .then(|| params.get("cwd").and_then(Value::as_str).map(PathBuf::from))
        .flatten();
        let successor_method = if method == "_proxy/initialize" {
            "initialize".to_owned()
        } else {
            method.clone()
        };
        let generated = self.generated_id();
        self.pending.insert(
            generated.clone(),
            Pending::Client {
                id: id.unwrap(),
                method,
                cwd,
                session_id: session,
            },
        );
        message["id"] = Value::String(generated);
        message["method"] = Value::String(SUCCESSOR_METHOD.into());
        message["params"] = successor_params(&successor_method, params);
        Ok(vec![message])
    }

    async fn handle_successor_message(&mut self, message: Value) -> Result<Vec<Value>> {
        let outer_id = message.get("id").cloned();
        let params = message.get("params").cloned().unwrap_or(Value::Null);
        let method = params
            .get("method")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let inner_params = params.get("params").cloned().unwrap_or(Value::Null);

        if method == "session/update" {
            self.observe_update(&inner_params).await?;
        }

        let mut forwarded = message;
        forwarded["method"] = Value::String(method.to_owned());
        forwarded["params"] = inner_params;
        if let Some(id) = outer_id {
            let generated = self.generated_id();
            self.pending.insert(
                id_key(&Value::String(generated.clone())),
                Pending::Agent { id },
            );
            forwarded["id"] = Value::String(generated);
        }
        Ok(vec![forwarded])
    }

    async fn response(&mut self, mut message: Value) -> Result<Vec<Value>> {
        let Some(key) = message.get("id").map(id_key) else {
            return Ok(vec![message]);
        };
        let Some(pending) = self.pending.remove(&key) else {
            return Ok(vec![message]);
        };

        match pending {
            Pending::Agent { id } => {
                message["id"] = id;
                Ok(vec![message])
            }
            Pending::Automatic { session_id } => self.complete_turn(&session_id, None).await,
            Pending::Client {
                id,
                method,
                cwd,
                session_id,
            } => {
                message["id"] = id;
                if matches!(
                    method.as_str(),
                    "session/new" | "session/load" | "session/resume"
                ) {
                    let id = message
                        .pointer("/result/sessionId")
                        .and_then(Value::as_str)
                        .or(session_id.as_deref());
                    if let Some(id) = id {
                        self.sessions.entry(id.to_owned()).or_default().cwd =
                            cwd.unwrap_or_else(|| PathBuf::from("."));
                    }
                }
                if method == "session/prompt"
                    && let Some(session_id) = session_id
                {
                    return self.complete_turn(&session_id, Some(message)).await;
                }
                Ok(vec![message])
            }
        }
    }

    async fn begin_prompt(&mut self, params: &Value) -> Result<()> {
        let Some(session_id) = session_id(params) else {
            return Ok(());
        };
        let text = prompt_text(params);
        let requested = requested_skills(&text);
        let session = self.sessions.entry(session_id.to_owned()).or_default();
        session.cancelled = false;
        session.followups = 0;
        let skills = load_session_skills(&self.roots, &session.cwd)?;
        if !session.active {
            session.active = skills.iter().any(|skill| {
                requested.contains(&skill.name)
                    && skill
                        .triggers
                        .iter()
                        .any(|trigger| trigger.event == "chat.message")
            });
        }
        if session.active {
            dispatch(&skills, session, Event::simple("chat.message")).await?;
        }
        Ok(())
    }

    async fn observe_update(&mut self, params: &Value) -> Result<()> {
        let Some(session_id) = session_id(params) else {
            return Ok(());
        };
        let Some(session) = self.sessions.get_mut(session_id) else {
            return Ok(());
        };
        if !session.active {
            return Ok(());
        }
        let Some(update) = params.get("update") else {
            return Ok(());
        };
        let kind = update
            .get("sessionUpdate")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if !matches!(kind, "tool_call" | "tool_call_update") {
            return Ok(());
        }
        let Some(call_id) = update.get("toolCallId").and_then(Value::as_str) else {
            return Ok(());
        };

        let call = session.tools.entry(call_id.to_owned()).or_default();
        merge_tool(call, update);
        let status = update
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let event = tool_event(call);
        let skills = load_session_skills(&self.roots, &session.cwd)?;
        if !call.before_dispatched && matches!(status, "pending" | "in_progress" | "") {
            call.before_dispatched = true;
            dispatch(
                &skills,
                session,
                Event {
                    name: "tool.execute.before",
                    ..event.clone()
                },
            )
            .await?;
        }
        if status == "completed" {
            dispatch(
                &skills,
                session,
                Event {
                    name: "tool.execute.after",
                    ..event
                },
            )
            .await?;
            session.tools.remove(call_id);
        } else if matches!(status, "failed" | "cancelled") {
            session.tools.remove(call_id);
        }
        Ok(())
    }

    async fn complete_turn(
        &mut self,
        session_id: &str,
        response: Option<Value>,
    ) -> Result<Vec<Value>> {
        let mut outputs = response.into_iter().collect::<Vec<_>>();
        let Some(session) = self.sessions.get_mut(session_id) else {
            return Ok(outputs);
        };
        if session.cancelled {
            session.queued.clear();
            return Ok(outputs);
        }
        if session.active {
            let skills = load_session_skills(&self.roots, &session.cwd)?;
            dispatch(&skills, session, Event::simple("session.idle")).await?;
        }
        if session.queued.is_empty() || session.followups >= MAX_AUTOMATIC_FOLLOWUPS {
            session.queued.clear();
            return Ok(outputs);
        }

        let text = session
            .queued
            .drain(..)
            .map(|(_, content)| content)
            .collect::<Vec<_>>()
            .join("\n\n");
        session.followups += 1;
        let generated = self.generated_id();
        self.pending.insert(
            generated.clone(),
            Pending::Automatic {
                session_id: session_id.to_owned(),
            },
        );
        outputs.push(json!({
            "jsonrpc": "2.0",
            "id": generated,
            "method": SUCCESSOR_METHOD,
            "params": {
                "method": "session/prompt",
                "params": {
                    "sessionId": session_id,
                    "prompt": [{"type": "text", "text": text}]
                }
            }
        }));
        Ok(outputs)
    }

    fn generated_id(&mut self) -> String {
        let id = format!("temper:{}", self.next_id);
        self.next_id += 1;
        id
    }
}

impl Event {
    fn simple(name: &'static str) -> Self {
        Self {
            name,
            tool: String::new(),
            command: String::new(),
            paths: vec![],
        }
    }
}

fn successor_params(method: &str, params: Value) -> Value {
    json!({"method": method, "params": params})
}

fn id_key(value: &Value) -> String {
    value
        .as_str()
        .map(str::to_owned)
        .unwrap_or_else(|| serde_json::to_string(value).unwrap_or_default())
}

fn session_id(params: &Value) -> Option<&str> {
    params.get("sessionId").and_then(Value::as_str)
}

fn prompt_text(params: &Value) -> String {
    params
        .get("prompt")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|block| block.get("type").and_then(Value::as_str) == Some("text"))
        .filter_map(|block| block.get("text").and_then(Value::as_str))
        .collect::<Vec<_>>()
        .join("\n")
}

fn requested_skills(text: &str) -> HashSet<String> {
    Regex::new(r"(?:^|\s)/([A-Za-z0-9_-]+)\b")
        .unwrap()
        .captures_iter(text)
        .map(|capture| capture[1].to_owned())
        .collect()
}

fn load_skills(roots: &[PathBuf]) -> Result<Vec<Skill>> {
    let mut seen = HashSet::new();
    let mut skills = Vec::new();
    for root in roots {
        let Ok(entries) = std::fs::read_dir(root) else {
            continue;
        };
        let mut entries = entries.filter_map(Result::ok).collect::<Vec<_>>();
        entries.sort_by_key(|entry| entry.file_name());
        for entry in entries {
            let path = entry.path().join("SKILL.md");
            if !path.is_file() {
                continue;
            }
            let raw = std::fs::read_to_string(&path)
                .with_context(|| format!("failed to read {}", path.display()))?;
            let Some((frontmatter, body)) = split_frontmatter(&raw) else {
                continue;
            };
            let meta: Frontmatter = serde_yaml::from_str(frontmatter)
                .with_context(|| format!("invalid frontmatter in {}", path.display()))?;
            let name = if meta.name.is_empty() {
                entry.file_name().to_string_lossy().into_owned()
            } else {
                meta.name
            };
            if meta.triggers.is_empty() || !seen.insert(name.clone()) {
                continue;
            }
            skills.push(Skill {
                name,
                once: meta.once,
                triggers: meta.triggers,
                content: body.to_owned(),
            });
        }
    }
    Ok(skills)
}

fn load_session_skills(roots: &[PathBuf], cwd: &Path) -> Result<Vec<Skill>> {
    let mut session_roots = vec![cwd.join(".agents/skills")];
    session_roots.extend_from_slice(roots);
    load_skills(&session_roots)
}

fn split_frontmatter(raw: &str) -> Option<(&str, &str)> {
    let rest = raw.strip_prefix("---\n")?;
    let (frontmatter, body) = rest.split_once("\n---\n")?;
    Some((frontmatter, body))
}

async fn dispatch(skills: &[Skill], session: &mut Session, event: Event) -> Result<()> {
    for skill in skills {
        for trigger in &skill.triggers {
            if !trigger_matches(trigger, &event)? {
                continue;
            }
            if trigger.action.as_deref() == Some("reset") {
                session.fired_once.remove(&skill.name);
                continue;
            }
            if skill.once && session.fired_once.contains(&skill.name) {
                continue;
            }
            if let Some(when) = &trigger.when
                && !command_succeeds(when, &session.cwd).await
            {
                continue;
            }
            if trigger.worktree.unwrap_or(false)
                && !inside_worktree(&session.cwd, &event.paths).await
            {
                continue;
            }
            if trigger.action.as_deref() == Some("fail") && event.name != "tool.execute.before" {
                continue;
            }
            let content = execute_bash_block(&skill.content, &session.cwd).await;
            if skill.once {
                session.fired_once.insert(skill.name.clone());
            }
            if !session.queued.iter().any(|(name, _)| name == &skill.name) {
                session.queued.push((skill.name.clone(), content));
            }
        }
    }
    Ok(())
}

fn trigger_matches(trigger: &Trigger, event: &Event) -> Result<bool> {
    if trigger.event != event.name {
        return Ok(false);
    }
    if let Some(pattern) = &trigger.tool
        && !Regex::new(pattern)?.is_match(&event.tool)
    {
        return Ok(false);
    }
    if let Some(pattern) = &trigger.command
        && !Regex::new(pattern)?.is_match(&event.command)
    {
        return Ok(false);
    }
    Ok(true)
}

async fn command_succeeds(command: &str, cwd: &Path) -> bool {
    Command::new("bash")
        .arg("-c")
        .arg(command)
        .current_dir(cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .is_ok_and(|status| status.success())
}

async fn inside_worktree(cwd: &Path, paths: &[PathBuf]) -> bool {
    if paths.is_empty() {
        return false;
    }
    let Ok(output) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .current_dir(cwd)
        .output()
        .await
    else {
        return false;
    };
    if !output.status.success() {
        return false;
    }
    let root = PathBuf::from(String::from_utf8_lossy(&output.stdout).trim());
    paths.iter().all(|path| {
        let path = if path.is_absolute() {
            path.clone()
        } else {
            cwd.join(path)
        };
        let path = path
            .canonicalize()
            .unwrap_or_else(|_| normalize_path(&path));
        path == root || path.starts_with(&root)
    })
}

fn normalize_path(path: &Path) -> PathBuf {
    use std::path::Component;

    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::ParentDir => {
                normalized.pop();
            }
            Component::CurDir => {}
            component => normalized.push(component.as_os_str()),
        }
    }
    normalized
}

async fn execute_bash_block(content: &str, cwd: &Path) -> String {
    let regex = Regex::new(r"(?ms)^```bash \{exec\}\n(.*?)^```").unwrap();
    let Some(capture) = regex.captures(content) else {
        return content.to_owned();
    };
    let Some(code) = capture.get(1) else {
        return content.to_owned();
    };
    let output = Command::new("bash")
        .arg("-c")
        .arg(code.as_str())
        .current_dir(cwd)
        .stdin(Stdio::null())
        .output()
        .await;
    let replacement = match output {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).trim().to_owned()
        }
        Ok(output) => format!(
            "{}\n\nCommand execution failed (exit code: {}).\n\n{}",
            String::from_utf8_lossy(&output.stdout).trim(),
            output.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&output.stderr).trim()
        ),
        Err(error) => format!("Command execution failed: {error}"),
    };
    regex.replace(content, replacement).into_owned()
}

fn merge_tool(call: &mut ToolCall, update: &Value) {
    if let Some(kind) = update.get("kind").and_then(Value::as_str) {
        call.kind = kind.to_owned();
    }
    if let Some(title) = update.get("title").and_then(Value::as_str) {
        call.title = title.to_owned();
    }
    if let Some(raw_input) = update.get("rawInput") {
        merge_value(&mut call.raw_input, raw_input);
    }
    if let Some(locations) = update.get("locations").and_then(Value::as_array) {
        call.locations = locations
            .iter()
            .filter_map(|location| location.get("path").and_then(Value::as_str))
            .map(PathBuf::from)
            .collect();
    }
}

fn merge_value(target: &mut Value, update: &Value) {
    match (target, update) {
        (Value::Object(target), Value::Object(update)) => {
            for (key, value) in update {
                target.insert(key.clone(), value.clone());
            }
        }
        (target, update) => *target = update.clone(),
    }
}

fn tool_event(call: &ToolCall) -> Event {
    let tool = match call.kind.as_str() {
        "execute" => "bash",
        "edit" | "delete" | "move" => "edit",
        other if !other.is_empty() => other,
        _ => call
            .raw_input
            .get("tool")
            .and_then(Value::as_str)
            .unwrap_or("other"),
    }
    .to_owned();
    let command = call
        .raw_input
        .get("command")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    let mut paths = call.locations.clone();
    for key in ["filePath", "path"] {
        if let Some(path) = call.raw_input.get(key).and_then(Value::as_str) {
            paths.push(PathBuf::from(path));
        }
    }
    if tool == "apply_patch"
        && let Some(patch) = call.raw_input.get("patchText").and_then(Value::as_str)
    {
        let regex =
            Regex::new(r"(?m)^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+)$").unwrap();
        paths.extend(
            regex
                .captures_iter(patch)
                .map(|capture| PathBuf::from(capture[1].trim())),
        );
    }
    Event {
        name: "tool.execute.before",
        tool,
        command,
        paths,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    fn rpc(id: i64, method: &str, params: Value) -> Value {
        json!({"jsonrpc":"2.0","id":id,"method":method,"params":params})
    }

    fn skill(root: &Path, name: &str, frontmatter: &str, body: &str) {
        let dir = root.join(name);
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("SKILL.md"),
            format!("---\nname: {name}\n{frontmatter}\n---\n{body}"),
        )
        .unwrap();
    }

    async fn establish(proxy: &mut Proxy, cwd: &Path) {
        let output = proxy
            .handle(rpc(1, "session/new", json!({"cwd":cwd,"mcpServers":[]})))
            .await
            .unwrap();
        let id = output[0]["id"].clone();
        proxy
            .handle(json!({"jsonrpc":"2.0","id":id,"result":{"sessionId":"s"}}))
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn forwards_unknown_messages_and_metadata() {
        let mut proxy = Proxy::new(vec![]);
        let request = rpc(7, "cursor/custom", json!({"x":1,"_meta":{"keep":true}}));
        let output = proxy.handle(request).await.unwrap();
        assert_eq!(output[0]["method"], SUCCESSOR_METHOD);
        assert_eq!(output[0]["params"]["method"], "cursor/custom");
        assert_eq!(output[0]["params"]["params"]["_meta"]["keep"], true);
        let id = output[0]["id"].clone();
        let response = json!({"jsonrpc":"2.0","id":id,"result":{"value":2,"extension":3}});
        let output = proxy.handle(response).await.unwrap();
        assert_eq!(
            output[0],
            json!({"jsonrpc":"2.0","id":7,"result":{"value":2,"extension":3}})
        );
    }

    #[tokio::test]
    async fn forwards_successor_permission_requests_unchanged() {
        let mut proxy = Proxy::new(vec![]);
        let output = proxy
            .handle(rpc(
                9,
                SUCCESSOR_METHOD,
                json!({"method":"session/request_permission","params":{"sessionId":"s","_meta":{"x":1}}}),
            ))
            .await
            .unwrap();
        assert_eq!(output[0]["method"], "session/request_permission");
        let id = output[0]["id"].clone();
        let output = proxy
            .handle(json!({"jsonrpc":"2.0","id":id,"result":{"outcome":{"outcome":"selected","optionId":"yes"}}}))
            .await
            .unwrap();
        assert_eq!(output[0]["id"], 9);
        assert_eq!(output[0]["result"]["outcome"]["optionId"], "yes");
    }

    #[tokio::test]
    async fn activates_only_after_generic_skill_request_and_batches_followup() {
        let temp = TempDir::new().unwrap();
        skill(
            temp.path(),
            "starter",
            "once: true\ntriggers:\n  - event: chat.message\n  - event: session.idle",
            "# starter",
        );
        let mut proxy = Proxy::new(vec![temp.path().to_owned()]);
        establish(&mut proxy, temp.path()).await;

        let first = proxy
            .handle(rpc(
                2,
                "session/prompt",
                json!({"sessionId":"s","prompt":[{"type":"text","text":"hello"}]}),
            ))
            .await
            .unwrap();
        let output = proxy
            .handle(json!({"jsonrpc":"2.0","id":first[0]["id"],"result":{"stopReason":"end_turn"}}))
            .await
            .unwrap();
        assert_eq!(output.len(), 1);

        let start = proxy
            .handle(rpc(
                3,
                "session/prompt",
                json!({"sessionId":"s","prompt":[{"type":"text","text":"/starter"}]}),
            ))
            .await
            .unwrap();
        let output = proxy
            .handle(json!({"jsonrpc":"2.0","id":start[0]["id"],"result":{"stopReason":"end_turn"}}))
            .await
            .unwrap();
        assert_eq!(output.len(), 2);
        assert_eq!(output[0]["id"], 3);
        assert_eq!(
            output[1]["params"]["params"]["prompt"][0]["text"],
            "# starter"
        );
    }

    #[tokio::test]
    async fn dispatches_successful_tools_but_not_failed_tools() {
        let temp = TempDir::new().unwrap();
        skill(
            temp.path(),
            "after",
            "triggers:\n  - event: tool.execute.after\n    tool: bash\n    command: cargo test",
            "# after",
        );
        skill(
            temp.path(),
            "starter",
            "once: true\ntriggers:\n  - event: chat.message",
            "# starter",
        );
        let mut proxy = Proxy::new(vec![temp.path().to_owned()]);
        establish(&mut proxy, temp.path()).await;
        proxy
            .handle(rpc(
                2,
                "session/prompt",
                json!({"sessionId":"s","prompt":[{"type":"text","text":"/starter"}]}),
            ))
            .await
            .unwrap();

        for (id, status) in [("failed", "failed"), ("ok", "completed")] {
            proxy
                .handle(json!({"jsonrpc":"2.0","method":SUCCESSOR_METHOD,"params":{"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call","toolCallId":id,"kind":"execute","status":"pending","rawInput":{"command":"cargo test"}}}}}))
                .await
                .unwrap();
            proxy
                .handle(json!({"jsonrpc":"2.0","method":SUCCESSOR_METHOD,"params":{"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call_update","toolCallId":id,"status":status}}}}))
                .await
                .unwrap();
        }
        let session = proxy.sessions.get("s").unwrap();
        assert!(session.queued.iter().any(|(name, _)| name == "after"));
        assert_eq!(
            session
                .queued
                .iter()
                .filter(|(name, _)| name == "after")
                .count(),
            1
        );
    }

    #[tokio::test]
    async fn cancellation_does_not_start_a_followup() {
        let temp = TempDir::new().unwrap();
        skill(
            temp.path(),
            "starter",
            "triggers:\n  - event: chat.message\n  - event: session.idle",
            "# starter",
        );
        let mut proxy = Proxy::new(vec![temp.path().to_owned()]);
        establish(&mut proxy, temp.path()).await;
        let prompt = proxy
            .handle(rpc(
                2,
                "session/prompt",
                json!({"sessionId":"s","prompt":[{"type":"text","text":"/starter"}]}),
            ))
            .await
            .unwrap();
        proxy
            .handle(json!({"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":"s"}}))
            .await
            .unwrap();
        let output = proxy
            .handle(
                json!({"jsonrpc":"2.0","id":prompt[0]["id"],"result":{"stopReason":"cancelled"}}),
            )
            .await
            .unwrap();
        assert_eq!(output.len(), 1);
        assert_eq!(output[0]["result"]["stopReason"], "cancelled");
    }

    #[tokio::test]
    async fn discovers_project_skills_from_the_session_cwd() {
        let temp = TempDir::new().unwrap();
        let project_skills = temp.path().join(".agents/skills");
        skill(
            &project_skills,
            "local",
            "triggers:\n  - event: chat.message",
            "# local",
        );
        let mut proxy = Proxy::new(vec![]);
        establish(&mut proxy, temp.path()).await;
        proxy
            .handle(rpc(
                2,
                "session/prompt",
                json!({"sessionId":"s","prompt":[{"type":"text","text":"/local"}]}),
            ))
            .await
            .unwrap();
        assert!(proxy.sessions["s"].active);
        assert_eq!(proxy.sessions["s"].queued[0].0, "local");
    }

    #[test]
    fn merges_partial_tool_updates_and_extracts_patch_paths() {
        let mut call = ToolCall::default();
        merge_tool(
            &mut call,
            &json!({"kind":"execute","rawInput":{"command":"git diff"}}),
        );
        merge_tool(&mut call, &json!({"rawInput":{"extra":true}}));
        assert_eq!(call.raw_input, json!({"command":"git diff","extra":true}));

        call.kind = "apply_patch".into();
        call.raw_input =
            json!({"patchText":"*** Update File: src/main.rs\n*** Move to: src/lib.rs"});
        let event = tool_event(&call);
        assert_eq!(
            event.paths,
            vec![PathBuf::from("src/main.rs"), PathBuf::from("src/lib.rs")]
        );
    }

    #[test]
    fn normalizes_parent_segments_before_worktree_checks() {
        assert_eq!(
            normalize_path(Path::new("/repo/src/../../outside")),
            PathBuf::from("/outside")
        );
    }
}
