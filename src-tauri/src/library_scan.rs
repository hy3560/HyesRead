use crate::{BookAdapter, BookMetadata};
use serde::Serialize;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{atomic::{AtomicBool, Ordering}, Arc, Mutex};
use walkdir::WalkDir;

const BATCH_SIZE: usize = 32;
const MAX_WARNINGS: usize = 10;

#[derive(Default)]
pub(crate) struct ScanRegistry(Mutex<HashMap<String, Arc<AtomicBool>>>);

impl ScanRegistry {
    pub(crate) fn register(&self, id: &str) -> Result<Arc<AtomicBool>, String> {
        if id.is_empty() || id.len() > 128 || !id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-') {
            return Err("扫描编号无效".into());
        }
        let mut active = self.0.lock().map_err(|_| "扫描状态不可用")?;
        if !active.is_empty() { return Err("已有书库扫描正在进行".into()); }
        let token = Arc::new(AtomicBool::new(false));
        active.insert(id.into(), token.clone());
        Ok(token)
    }

    pub(crate) fn cancel(&self, id: &str) -> Result<bool, String> {
        let active = self.0.lock().map_err(|_| "扫描状态不可用")?;
        if let Some(token) = active.get(id) {
            token.store(true, Ordering::Relaxed);
            return Ok(true);
        }
        Ok(false)
    }

    pub(crate) fn finish(&self, id: &str) -> Result<(), String> {
        self.0.lock().map_err(|_| "扫描状态不可用")?.remove(id);
        Ok(())
    }
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ScanProgress {
    pub scan_id: String,
    pub scanned: usize,
    pub skipped: usize,
    pub books: Vec<BookMetadata>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ScanResult {
    pub books: Vec<BookMetadata>,
    pub scanned: usize,
    pub skipped: usize,
    pub cancelled: bool,
    pub complete: bool,
    pub warnings: Vec<String>,
}

fn is_book(path: &Path) -> bool {
    matches!(path.extension().and_then(|value| value.to_str()).unwrap_or("").to_ascii_lowercase().as_str(),
        "epub" | "pdf" | "mobi" | "azw3" | "kf8" | "fb2" | "fbz" | "cbz" | "txt" | "md")
}

// Walking and metadata parsing run on a blocking worker, never on the command runtime.
// A partial or cancelled result must not be used to remove existing library records.
pub(crate) fn scan(
    root: PathBuf,
    id: String,
    cancel: &AtomicBool,
    mut progress: impl FnMut(ScanProgress),
) -> Result<ScanResult, String> {
    if !root.is_dir() { return Err("书库目录不存在或无法访问".into()); }
    let mut result = ScanResult { books: Vec::new(), scanned: 0, skipped: 0, cancelled: false, complete: false, warnings: Vec::new() };
    let mut batch = Vec::with_capacity(BATCH_SIZE);
    if !cancel.load(Ordering::Relaxed) {
        progress(ScanProgress { scan_id: id.clone(), scanned: 0, skipped: 0, books: Vec::new() });
    }
    for entry in WalkDir::new(&root).follow_links(false).into_iter()
        .filter_entry(|entry| entry.depth() == 0 || !entry.file_name().to_string_lossy().starts_with('.')) {
        if cancel.load(Ordering::Relaxed) { result.cancelled = true; break; }
        let entry = match entry {
            Ok(entry) => entry,
            Err(error) => {
                if error.depth() == 0 { return Err(format!("无法读取书库目录：{error}")); }
                result.skipped += 1;
                if result.warnings.len() < MAX_WARNINGS { result.warnings.push(format!("无法读取部分目录：{error}")); }
                continue;
            }
        };
        if !entry.file_type().is_file() || !is_book(entry.path()) { continue; }
        let path = entry.into_path();
        if std::fs::metadata(&path).is_err() {
            result.skipped += 1;
            continue;
        }
        let book = BookAdapter::process(path);
        result.scanned += 1;
        batch.push(book.clone());
        result.books.push(book);
        if batch.len() == BATCH_SIZE {
            progress(ScanProgress { scan_id: id.clone(), scanned: result.scanned, skipped: result.skipped, books: std::mem::take(&mut batch) });
        }
    }
    result.cancelled |= cancel.load(Ordering::Relaxed);
    result.complete = !result.cancelled && result.skipped == 0;
    if !batch.is_empty() {
        progress(ScanProgress { scan_id: id, scanned: result.scanned, skipped: result.skipped, books: batch });
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Instant, SystemTime, UNIX_EPOCH};

    fn fixture(count: usize) -> PathBuf {
        let nonce = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let root = std::env::temp_dir().join(format!("hyesread-batch-{}-{nonce}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        for index in 0..count { std::fs::write(root.join(format!("book-{index:05}.txt")), b"book body").unwrap(); }
        root
    }

    #[test]
    fn scans_ten_thousand_real_files_in_bounded_batches() {
        let root = fixture(10_000);
        std::fs::create_dir_all(root.join(".hidden")).unwrap();
        std::fs::write(root.join(".hidden/ignored.txt"), b"hidden").unwrap();
        std::fs::write(root.join("notes.exe"), b"not a book").unwrap();
        let start = Instant::now();
        let mut received = 0;
        let result = scan(root.clone(), "real-files".into(), &AtomicBool::new(false), |batch| {
            assert!(batch.books.len() <= BATCH_SIZE);
            received += batch.books.len();
            assert_eq!(batch.scanned, received);
        }).unwrap();
        eprintln!("10k real-file scan: {} ms, {} batches", start.elapsed().as_millis(), 10_000usize.div_ceil(BATCH_SIZE));
        assert_eq!(result.books.len(), 10_000);
        assert_eq!(received, 10_000);
        assert!(result.complete);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn scans_one_thousand_mixed_books_and_keeps_unreadable_metadata_as_fallback() {
        let root = fixture(0);
        let epub = Path::new(env!("CARGO_MANIFEST_DIR")).join("../tests/fixtures/hyesread-acceptance.epub");
        for index in 0..1_000 {
            match index % 4 {
                0 | 1 => { std::fs::copy(&epub, root.join(format!("book-{index}.epub"))).unwrap(); }
                2 => { std::fs::write(root.join(format!("book-{index}.pdf")), b"invalid PDF metadata").unwrap(); }
                _ => { std::fs::write(root.join(format!("book-{index}.txt")), b"reading text").unwrap(); }
            }
        }
        let start = Instant::now();
        let result = scan(root.clone(), "mixed".into(), &AtomicBool::new(false), |_| {}).unwrap();
        eprintln!("1k mixed-book metadata scan: {} ms", start.elapsed().as_millis());
        assert_eq!(result.books.len(), 1_000);
        assert_eq!(result.books.iter().filter(|book| book.format == "EPUB").count(), 500);
        assert_eq!(result.books.iter().filter(|book| book.format == "PDF").count(), 250);
        assert!(result.complete);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn cancellation_stops_before_the_next_batch_and_registry_is_reusable() {
        let root = fixture(100);
        let registry = ScanRegistry::default();
        let token = registry.register("first").unwrap();
        assert!(registry.register("second").is_err());
        let result = scan(root.clone(), "first".into(), &token, |batch| { if batch.scanned > 0 { registry.cancel("first").unwrap(); } }).unwrap();
        assert!(result.cancelled);
        assert!(!result.complete);
        assert_eq!(result.scanned, BATCH_SIZE);
        registry.finish("first").unwrap();
        assert!(!registry.cancel("first").unwrap());
        assert!(registry.register("second").is_ok());
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_missing_root_and_honors_cancel_before_work_starts() {
        let root = fixture(2);
        let result = scan(root.clone(), "cancelled".into(), &AtomicBool::new(true), |_| panic!("unexpected batch")).unwrap();
        assert_eq!(result.scanned, 0);
        assert!(result.cancelled);
        assert!(scan(root.join("missing"), "missing".into(), &AtomicBool::new(false), |_| {}).is_err());
        std::fs::remove_dir_all(root).unwrap();
    }
}
