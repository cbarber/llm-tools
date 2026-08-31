use anyhow::{Context, Result};
use std::path::PathBuf;
use temper_acp::Proxy;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

#[tokio::main]
async fn main() -> Result<()> {
    let roots = skill_roots();
    let mut proxy = Proxy::new(roots);
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    let mut stdout = tokio::io::stdout();

    while let Some(line) = lines.next_line().await? {
        let message = serde_json::from_str(&line).context("invalid JSON-RPC message")?;
        for output in proxy.handle(message).await? {
            stdout
                .write_all(serde_json::to_string(&output)?.as_bytes())
                .await?;
            stdout.write_all(b"\n").await?;
            stdout.flush().await?;
        }
    }

    Ok(())
}

fn skill_roots() -> Vec<PathBuf> {
    if let Some(roots) = std::env::var_os("TEMPER_SKILLS_DIRS") {
        return std::env::split_paths(&roots).collect();
    }

    let mut roots = Vec::new();
    if let Some(root) = std::env::var_os("AGENTS_SKILLS_DIR") {
        roots.push(root.into());
    }
    if let Some(home) = std::env::var_os("HOME") {
        roots.push(PathBuf::from(home).join(".agents/skills"));
    }
    roots
}
