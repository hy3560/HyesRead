use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::fs::File;
use std::io::Read;
use epub::doc::EpubDoc;
use mobi::Mobi; 
use base64::{Engine as _, engine::general_purpose};
use walkdir::WalkDir;
use rayon::prelude::*;

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
        "epub", "mobi", "azw3", "kf8", "pdf", "txt", 
        "cbz", "cbr", "doc", "docx", "rtf", "md", "fb2"
    ];

    let entries: Vec<PathBuf> = WalkDir::new(root)
        .max_depth(5)
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
async fn fetch_remote_models(api_url: String, api_key: String) -> Result<Vec<String>, String> {
    let base_url = api_url.trim_end_matches('/');
    let target_url = if base_url.ends_with("/models") { base_url.to_string() } else { format!("{}/models", base_url) };
    let client = reqwest::Client::builder().timeout(std::time::Duration::from_secs(10)).build().map_err(|e| e.to_string())?;
    
    let mut request = client.get(&target_url);
    if !api_key.is_empty() {
        request = request.header("Authorization", format!("Bearer {}", api_key));
    }
    
    let res = request.send().await.map_err(|e| e.to_string())?;
    let status = res.status();
    
    if status.is_success() {
        let json: serde_json::Value = res.json().await.map_err(|e| e.to_string())?;
        let mut model_ids: Vec<String> = json["data"].as_array().unwrap_or(&vec![]).iter().filter_map(|m| m["id"].as_str().map(|s| s.to_string())).collect();
        model_ids.sort();
        Ok(model_ids)
    } else {
        Err(format!("HTTP Error: {}", status))
    }
}

#[tauri::command]
async fn delete_book(path: String) -> Result<(), String> {
    let p = Path::new(&path);
    if p.exists() && p.is_file() {
        std::fs::remove_file(p).map_err(|e| format!("物理文件销毁失败: {}", e))
    } else {
        Err("文件已不存在或已被其它程序清理".into())
    }
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![
            scan_library, 
            import_files, 
            fetch_remote_models,
            delete_book,
            open_book
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}