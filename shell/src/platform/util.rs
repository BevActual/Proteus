use std::process::Command;

pub(crate) fn sh_ok(cmd: &str, args: &[&str]) -> Result<(), String> {
    let status = Command::new(cmd)
        .args(args)
        .status()
        .map_err(|e| format!("{cmd}: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{cmd} failed"))
    }
}

pub(crate) fn which_like(name: &str) -> Result<std::path::PathBuf, ()> {
    let out = Command::new("which").arg(name).output().map_err(|_| ())?;
    if !out.status.success() {
        return Err(());
    }
    let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if p.is_empty() {
        Err(())
    } else {
        Ok(std::path::PathBuf::from(p))
    }
}
