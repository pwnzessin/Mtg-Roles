use std::fs;
use std::process::Command;

#[tauri::command]
fn read_file_text(path: String) -> Result<String, String> {
    fs::read_to_string(&path).map_err(|e| format!("read failed: {}", e))
}

#[tauri::command]
fn write_file_text(path: String, content: String) -> Result<(), String> {
    fs::write(&path, content).map_err(|e| format!("write failed: {}", e))
}

#[tauri::command]
fn run_powershell_script(script_path: String, args: Vec<String>) -> Result<String, String> {
    let mut cmd = Command::new("powershell");
    cmd.arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(script_path);

    for arg in args {
        cmd.arg(arg);
    }

    let output = cmd.output().map_err(|e| format!("spawn failed: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if output.status.success() {
        Ok(stdout)
    } else {
        Err(format!("script failed\n{}\n{}", stdout, stderr))
    }
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            read_file_text,
            write_file_text,
            run_powershell_script
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
