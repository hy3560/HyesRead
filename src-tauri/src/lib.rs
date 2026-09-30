use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::fs::File;
use std::io::Read;
use std::ffi::OsString;
use std::sync::Mutex;
use epub::doc::EpubDoc;
use mobi::Mobi; 
use base64::{Engine as _, engine::general_purpose};
use walkdir::WalkDir;
use rayon::prelude::*;
use tauri::{Emitter, Manager, State};

#[derive(Default)]
struct OpenFileQueue {
    frontend_ready: Mutex<bool>,
    pending: Mutex<Vec<String>>,
}

fn supported_book_path(path: &Path, cwd: &Path) -> Option<String> {
    let mut path = PathBuf::from(path);
    if path.is_relative() {
        path = cwd.join(path);
    }
    let extension = path.extension()?.to_str()?.to_ascii_lowercase();
    if !matches!(extension.as_str(), "epub" | "pdf" | "mobi" | "azw3" | "kf8" | "fb2" | "fbz" | "cbz" | "txt" | "md") {
        return None;
    }
    path.is_file().then(|| path.to_string_lossy().into_owned())
}

fn paths_from_args(args: impl IntoIterator<Item = OsString>, cwd: &Path) -> Vec<String> {
    args.into_iter()
        .filter_map(|arg| supported_book_path(Path::new(&arg), cwd))
        .collect()
}

fn route_open_files(app: &tauri::AppHandle, paths: Vec<String>) {
    if paths.is_empty() {
        return;
    }
    let state = app.state::<OpenFileQueue>();
    let Ok(frontend_ready) = state.frontend_ready.lock() else {
        return;
    };
    if !*frontend_ready {
        if let Ok(mut pending) = state.pending.lock() {
            pending.extend(paths);
        }
        return;
    }
    drop(frontend_ready);

    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
    let _ = app.emit("hyesread:open-files", paths);
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct BookMetadata {
    pub title: String,
    pub author: String,
    pub path: String,
    pub format: String,
    pub size: f64,
    pub cover: Option<String>, 
}

struct BookAdapter;

impl BookAdapter {
    fn process(path: PathBuf) -> BookMetadata {
        let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("").to_lowercase();
        let path_str = path.to_string_lossy().to_string();
        let file_stem = path.file_stem().unwrap_or_default().to_string_lossy().to_string();
        let size_mb = std::fs::metadata(&path).map(|m| m.len() as f64 / 1048576.0).unwrap_or(0.0);

        match ext.as_str() {
            "epub" => Self::parse_epub(&path, file_stem, path_str, size_mb),
            "mobi" | "azw3" | "kf8" => Self::parse_mobi(&path, file_stem, path_str, size_mb, &ext),
            "pdf" => Self::parse_pdf(&path, file_stem, path_str, size_mb),
            "cbz" => Self::parse_cbz(&path, file_stem, path_str, size_mb),
            _ => Self::parse_generic(file_stem, path_str, size_mb, ext),
        }
    }

    fn parse_epub(p: &Path, stem: String, ps: String, size: f64) -> BookMetadata {
        if let Ok(mut doc) = EpubDoc::new(p) {
            let title = doc.mdata("title").map(|m| m.value.clone()).unwrap_or(stem);
            let author = doc.mdata("creator").map(|m| m.value.clone()).unwrap_or("未知".into());
            let cover = doc.get_cover().map(|(d, m)| format!("data:{};base64,{}", m, general_purpose::STANDARD.encode(&d)));
            return BookMetadata { title, author, path: ps, format: "EPUB".into(), size, cover };
        }
        Self::parse_generic(stem, ps, size, "EPUB".into())
    }

    fn parse_mobi(p: &Path, stem: String, ps: String, size: f64, ext: &str) -> BookMetadata {
        if let Ok(mobi) = Mobi::new(p) {
            let title = mobi.title().map(|t| t.to_string()).unwrap_or(stem);
            let author = mobi.author().map(|a| a.to_string()).unwrap_or("未知".into());
            return BookMetadata { title, author, path: ps, format: ext.to_uppercase(), size, cover: None };
        }
        Self::parse_generic(stem, ps, size, ext.to_uppercase())
    }

    fn parse_pdf(p: &Path, stem: String, ps: String, size: f64) -> BookMetadata {
        if let Ok(doc) = lopdf::Document::load(p) {
            let title = doc.trailer.get(b"Info")
                .and_then(|obj| obj.as_reference())
                .and_then(|id| doc.get_dictionary(id))
                .and_then(|dict| dict.get(b"Title"))
                .and_then(|obj| obj.as_str())
                .map(|s| String::from_utf8_lossy(s).to_string())
                .unwrap_or(stem);
            
            return BookMetadata { title, author: "PDF Document".into(), path: ps, format: "PDF".into(), size, cover: None };
        }
        Self::parse_generic(stem, ps, size, "PDF".into())
    }

    fn parse_cbz(p: &Path, stem: String, ps: String, size: f64) -> BookMetadata {
        if let Ok(file) = File::open(p) {
            if let Ok(mut archive) = zip::ZipArchive::new(file) {
                for i in 0..archive.len() {
                    if let Ok(mut f) = archive.by_index(i) {
                        let name = f.name().to_lowercase();
                        if name.ends_with(".jpg") || name.ends_with(".png") || name.ends_with(".jpeg") {
                            let mut buf = Vec::new();
                            if f.read_to_end(&mut buf).is_ok() {
                                let b64 = general_purpose::STANDARD.encode(&buf);
                                return BookMetadata { 
                                    title: stem, author: "Comic".into(), path: ps, 
                                    format: "CBZ".into(), size, cover: Some(format!("data:image/jpeg;base64,{}", b64)) 
                                };
                            }
                        }
                    }
                }
            }
        }
        Self::parse_generic(stem, ps, size, "CBZ".into())
    }

    fn parse_generic(t: String, p: String, s: f64, f: String) -> BookMetadata {
        BookMetadata { title: t, author: "Local".into(), path: p, format: f.to_uppercase(), size: s, cover: None }
    }
}

#[tauri::command]
async fn scan_library(folder_path: String) -> Result<Vec<BookMetadata>, String> {
    let mut clean_path = folder_path.as_str();
    if clean_path.starts_with(r"\\?\") { clean_path = &clean_path[4..]; }
    let root = Path::new(clean_path.trim_matches('"'));
    
    if !root.exists() { return Err("目录不存在".into()); }

    let formats = vec![
        "epub", "mobi", "azw3", "kf8", "pdf", "txt", "md",
        "cbz", "fb2", "fbz"
    ];

    let entries: Vec<PathBuf> = WalkDir::new(root)
        .max_depth(5)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_file())
        .map(|e| e.path().to_path_buf())
        .filter(|p| {
            let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("").to_lowercase();
            formats.contains(&ext.as_str())
        })
        .collect();

    let books: Vec<BookMetadata> = entries.into_par_iter()
        .map(BookAdapter::process)
        .collect();

    Ok(books)
}

#[tauri::command]
async fn import_files(file_paths: Vec<String>) -> Result<Vec<BookMetadata>, String> {
    let books: Vec<BookMetadata> = file_paths.into_par_iter()
        .map(PathBuf::from)
        .filter(|p| p.is_file())
        .map(BookAdapter::process)
        .collect();

    Ok(books)
}

#[tauri::command]
async fn read_text_book(path: String) -> Result<String, String> {
    let p = Path::new(&path);
    if !p.is_file() { return Err("目标文件不存在".into()); }
    let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("").to_ascii_lowercase();
    if ext != "txt" && ext != "md" { return Err("仅支持读取 TXT 和 Markdown 文本".into()); }
    std::fs::read_to_string(p).or_else(|_| {
        let bytes = std::fs::read(p)?;
        Ok::<_, std::io::Error>(String::from_utf8_lossy(&bytes).into_owned())
    }).map_err(|e| format!("读取文本失败: {e}"))
}

#[tauri::command]
async fn reveal_book(path: String) -> Result<(), String> {
    let p = Path::new(&path);
    if !p.is_file() { return Err("目标文件不存在".into()); }
    opener::reveal(p).map_err(|e| format!("无法在文件管理器中显示: {e}"))
}

#[tauri::command]
async fn prepare_book_read(app: tauri::AppHandle, path: String) -> Result<(), String> {
    let p = Path::new(&path);
    if !p.is_file() { return Err("目标文件不存在".into()); }
    let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("").to_ascii_lowercase();
    if !["epub", "pdf", "mobi", "azw3", "kf8", "fb2", "fbz", "cbz", "txt", "md"].contains(&ext.as_str()) {
        return Err("不支持此文件格式".into());
    }
    app.asset_protocol_scope().allow_file(p).map_err(|e| format!("无法打开此文件: {e}"))
}

#[tauri::command]
async fn open_book(path: String) -> Result<(), String> {
    let p = Path::new(&path);
    if p.exists() {
        opener::open(p).map_err(|e| format!("系统级唤起失败: {}", e))
    } else {
        Err("目标物理文件已丢失".into())
    }
}

#[tauri::command]
fn take_open_files(state: State<'_, OpenFileQueue>) -> Result<Vec<String>, String> {
    let mut ready = state.frontend_ready.lock().map_err(|e| e.to_string())?;
    let mut pending = state.pending.lock().map_err(|e| e.to_string())?;
    *ready = true;
    Ok(std::mem::take(&mut *pending))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(OpenFileQueue::default())
        .plugin(tauri_plugin_single_instance::init(|app, argv, cwd| {
            let paths = paths_from_args(argv.into_iter().skip(1).map(OsString::from), Path::new(&cwd));
            route_open_files(app, paths);
        }))
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .setup(|app| {
            let cwd = std::env::current_dir().unwrap_or_default();
            let paths = paths_from_args(std::env::args_os().skip(1), &cwd);
            if !paths.is_empty() {
                app.state::<OpenFileQueue>()
                    .pending
                    .lock()
                    .map_err(|_| std::io::Error::other("打开文件队列不可用"))?
                    .extend(paths);
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            scan_library, 
            import_files, 
            read_text_book,
            open_book,
            reveal_book,
            prepare_book_read,
            take_open_files
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::supported_book_path;
    use std::path::Path;

    #[test]
    fn resolves_existing_supported_books_and_rejects_other_paths() {
        let root = std::env::temp_dir().join(format!("hyesread-file-association-{}", std::process::id()));
        std::fs::create_dir_all(&root).expect("create temporary book directory");
        let book = root.join("book.EPUB");
        std::fs::write(&book, b"test book").expect("create temporary book");

        assert_eq!(
            supported_book_path(Path::new("book.EPUB"), &root),
            Some(book.to_string_lossy().into_owned())
        );
        assert_eq!(supported_book_path(Path::new("missing.pdf"), &root), None);
        assert_eq!(supported_book_path(Path::new("image.png"), &root), None);

        std::fs::remove_dir_all(root).expect("remove temporary book directory");
    }
}
