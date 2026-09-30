use quick_xml::events::{BytesStart, Event};
use quick_xml::Reader;
use serde::Serialize;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::io::AsyncWriteExt;
use url::Url;

const MAX_FEED_BYTES: usize = 5 * 1024 * 1024;
const MAX_BOOK_BYTES: u64 = 1024 * 1024 * 1024;

#[derive(Debug, Clone, Serialize)]
pub struct OpdsLink {
    pub href: String,
    pub rel: String,
    pub media_type: String,
    pub title: String,
    pub length: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OpdsEntry {
    pub id: String,
    pub title: String,
    pub author: String,
    pub summary: String,
    pub links: Vec<OpdsLink>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OpdsFeed {
    pub title: String,
    pub entries: Vec<OpdsEntry>,
    pub links: Vec<OpdsLink>,
}

#[derive(Default)]
struct EntryBuilder {
    id: String,
    title: String,
    author: String,
    summary: String,
    links: Vec<OpdsLink>,
}

#[derive(Clone, Copy)]
enum TextField {
    FeedTitle,
    EntryId,
    EntryTitle,
    EntryAuthor,
    EntrySummary,
}

fn validate_http_url(raw: &str) -> Result<Url, String> {
    let url = Url::parse(raw.trim()).map_err(|_| "目录地址无效".to_string())?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return Err("目录只支持 HTTP 或 HTTPS 地址".to_string());
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err("请使用不含账号密码的目录地址".to_string());
    }
    Ok(url)
}

fn local_name(name: &[u8]) -> String {
    let name = name.rsplit(|byte| *byte == b':').next().unwrap_or(name);
    String::from_utf8_lossy(name).into_owned()
}

fn link_from_element(
    element: &BytesStart<'_>,
    reader: &Reader<&[u8]>,
    base_url: &Url,
) -> Result<OpdsLink, String> {
    let mut href = None;
    let mut rel = "alternate".to_string();
    let mut media_type = String::new();
    let mut title = String::new();
    let mut length = None;
    for attribute in element.attributes().with_checks(false) {
        let attribute = attribute.map_err(|error| format!("目录链接格式无效：{error}"))?;
        let value = attribute
            .decode_and_unescape_value(reader.decoder())
            .map_err(|error| format!("目录链接编码无效：{error}"))?
            .into_owned();
        match attribute.key.local_name().as_ref() {
            b"href" => href = Some(value),
            b"rel" => rel = value,
            b"type" => media_type = value,
            b"title" => title = value,
            b"length" => length = value.parse().ok(),
            _ => {}
        }
    }
    let href = href.ok_or_else(|| "目录链接缺少地址".to_string())?;
    let resolved = base_url
        .join(&href)
        .map_err(|_| "目录包含无效链接".to_string())?;
    if !matches!(resolved.scheme(), "http" | "https") {
        return Err("目录包含不支持的链接类型".to_string());
    }
    Ok(OpdsLink {
        href: resolved.to_string(),
        rel,
        media_type,
        title,
        length,
    })
}

fn push_text(
    field: TextField,
    value: &str,
    feed_title: &mut String,
    entry: &mut Option<EntryBuilder>,
) {
    let target = match field {
        TextField::FeedTitle => feed_title,
        TextField::EntryId => &mut entry.get_or_insert_with(EntryBuilder::default).id,
        TextField::EntryTitle => &mut entry.get_or_insert_with(EntryBuilder::default).title,
        TextField::EntryAuthor => &mut entry.get_or_insert_with(EntryBuilder::default).author,
        TextField::EntrySummary => &mut entry.get_or_insert_with(EntryBuilder::default).summary,
    };
    target.push_str(value);
}

fn clean_text(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn parse_atom_feed(xml: &str, base_url: &Url) -> Result<OpdsFeed, String> {
    if xml.len() > MAX_FEED_BYTES {
        return Err("目录内容超过 5 MB，已停止读取".to_string());
    }
    let mut reader = Reader::from_str(xml);
    reader.config_mut().trim_text(false);
    let mut stack = Vec::<String>::new();
    let mut text_field = None;
    let mut feed_title = String::new();
    let mut entries = Vec::new();
    let mut feed_links = Vec::new();
    let mut entry = None::<EntryBuilder>;

    loop {
        match reader.read_event() {
            Ok(Event::Start(element)) => {
                let name = local_name(element.local_name().as_ref());
                let parent = stack.last().map(String::as_str).unwrap_or_default();
                match name.as_str() {
                    "entry" => entry = Some(EntryBuilder::default()),
                    "title" if entry.is_some() => text_field = Some(TextField::EntryTitle),
                    "title" => text_field = Some(TextField::FeedTitle),
                    "id" if entry.is_some() => text_field = Some(TextField::EntryId),
                    "name" if parent == "author" && entry.is_some() => {
                        text_field = Some(TextField::EntryAuthor)
                    }
                    "summary" | "content" if entry.is_some() => {
                        text_field = Some(TextField::EntrySummary)
                    }
                    "link" => {
                        let link = link_from_element(&element, &reader, base_url)?;
                        if let Some(current) = entry.as_mut() {
                            current.links.push(link);
                        } else {
                            feed_links.push(link);
                        }
                    }
                    _ => {}
                }
                stack.push(name);
            }
            Ok(Event::Empty(element)) if element.local_name().as_ref() == b"link" => {
                let link = link_from_element(&element, &reader, base_url)?;
                if let Some(current) = entry.as_mut() {
                    current.links.push(link);
                } else {
                    feed_links.push(link);
                }
            }
            Ok(Event::Text(text)) => {
                if let Some(field) = text_field {
                    let decoded = text
                        .decode()
                        .map_err(|error| format!("目录文字编码无效：{error}"))?;
                    let unescaped = quick_xml::escape::unescape(&decoded)
                        .map_err(|error| format!("目录文字格式无效：{error}"))?;
                    push_text(field, &unescaped, &mut feed_title, &mut entry);
                }
            }
            Ok(Event::CData(text)) => {
                if let Some(field) = text_field {
                    let decoded = text
                        .decode()
                        .map_err(|error| format!("目录文字编码无效：{error}"))?;
                    push_text(field, &decoded, &mut feed_title, &mut entry);
                }
            }
            Ok(Event::End(element)) => {
                let name = local_name(element.local_name().as_ref());
                let parent = stack
                    .iter()
                    .rev()
                    .nth(1)
                    .map(String::as_str)
                    .unwrap_or_default();
                match name.as_str() {
                    "entry" => {
                        if let Some(current) = entry.take() {
                            let item = OpdsEntry {
                                id: clean_text(&current.id),
                                title: clean_text(&current.title),
                                author: clean_text(&current.author),
                                summary: clean_text(&current.summary),
                                links: current.links,
                            };
                            if !item.title.is_empty() {
                                entries.push(item);
                            }
                        }
                        text_field = None;
                    }
                    "title" | "id" | "summary" | "content" => text_field = None,
                    "name" if parent == "author" => text_field = None,
                    _ => {}
                }
                stack.pop();
            }
            Ok(Event::Eof) => break,
            Ok(_) => {}
            Err(error) => return Err(format!("目录 XML 格式无效：{error}")),
        }
    }
    let title = clean_text(&feed_title);
    if title.is_empty() && entries.is_empty() {
        return Err("目录中没有可显示的书籍或分类".to_string());
    }
    Ok(OpdsFeed {
        title: if title.is_empty() {
            base_url.host_str().unwrap_or("OPDS").to_string()
        } else {
            title
        },
        entries,
        links: feed_links,
    })
}

fn http_client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::limited(8))
        .user_agent(concat!("HyesRead/", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|error| format!("无法初始化网络连接：{error}"))
}

async fn read_feed_response(response: reqwest::Response) -> Result<String, String> {
    if let Some(length) = response.content_length() {
        if length > MAX_FEED_BYTES as u64 {
            return Err("目录内容超过 5 MB，已停止读取".to_string());
        }
    }
    let mut response = response;
    let mut bytes = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| format!("目录读取失败：{error}"))?
    {
        if bytes.len().saturating_add(chunk.len()) > MAX_FEED_BYTES {
            return Err("目录内容超过 5 MB，已停止读取".to_string());
        }
        bytes.extend_from_slice(&chunk);
    }
    String::from_utf8(bytes).map_err(|_| "目录不是有效的 UTF-8 Atom 文本".to_string())
}

pub async fn fetch_feed(raw_url: &str) -> Result<OpdsFeed, String> {
    let url = validate_http_url(raw_url)?;
    let response = http_client()?
        .get(url.clone())
        .send()
        .await
        .map_err(|error| format!("无法连接目录：{error}"))?
        .error_for_status()
        .map_err(|error| format!("目录返回错误状态：{error}"))?;
    let response_url = response.url().clone();
    let xml = read_feed_response(response).await?;
    parse_atom_feed(&xml, &response_url)
}

fn temporary_download_path(destination: &Path) -> Result<PathBuf, String> {
    let parent = destination
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .ok_or_else(|| "下载位置无效".to_string())?;
    let filename = destination
        .file_name()
        .ok_or_else(|| "下载文件名无效".to_string())?
        .to_string_lossy();
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    Ok(parent.join(format!(
        ".{filename}.hyesread-{}-{nonce}.part",
        std::process::id()
    )))
}

pub async fn download_book(raw_url: &str, destination: &str) -> Result<String, String> {
    let url = validate_http_url(raw_url)?;
    let destination = PathBuf::from(destination);
    let extension = destination
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if !matches!(
        extension.as_str(),
        "epub" | "pdf" | "mobi" | "azw3" | "kf8" | "fb2" | "fbz" | "cbz" | "txt" | "md"
    ) {
        return Err("下载路径必须使用 HyesRead 支持的电子书格式".to_string());
    }
    if destination.exists() {
        return Err("目标文件已存在，请选择其他文件名".to_string());
    }
    let parent = destination
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .ok_or_else(|| "下载位置无效".to_string())?;
    if !parent.is_dir() {
        return Err("下载文件夹不存在".to_string());
    }
    let temporary = temporary_download_path(&destination)?;
    let mut temporary_created = false;
    let result = async {
        let mut response = http_client()?
            .get(url)
            .send()
            .await
            .map_err(|error| format!("下载连接失败：{error}"))?
            .error_for_status()
            .map_err(|error| format!("下载返回错误状态：{error}"))?;
        if response
            .content_length()
            .is_some_and(|length| length > MAX_BOOK_BYTES)
        {
            return Err("电子书大于 1 GB，已停止下载".to_string());
        }
        let mut file = tokio::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
            .await
            .map_err(|error| format!("无法创建临时下载文件：{error}"))?;
        temporary_created = true;
        let mut total = 0u64;
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|error| format!("下载中断：{error}"))?
        {
            total = total.saturating_add(chunk.len() as u64);
            if total > MAX_BOOK_BYTES {
                return Err("电子书大于 1 GB，已停止下载".to_string());
            }
            file.write_all(&chunk)
                .await
                .map_err(|error| format!("写入下载文件失败：{error}"))?;
        }
        if total == 0 {
            return Err("服务器返回了空文件".to_string());
        }
        file.flush()
            .await
            .map_err(|error| format!("保存下载文件失败：{error}"))?;
        drop(file);
        if destination.exists() {
            return Err("目标文件已存在，请选择其他文件名".to_string());
        }
        tokio::fs::rename(&temporary, &destination)
            .await
            .map_err(|error| format!("无法保存电子书：{error}"))?;
        Ok(destination.to_string_lossy().into_owned())
    }
    .await;
    if result.is_err() && temporary_created {
        let _ = tokio::fs::remove_file(&temporary).await;
    }
    result
}

#[cfg(test)]
mod tests {
    use super::{download_book, parse_atom_feed, validate_http_url};

    #[test]
    fn parses_navigation_acquisition_and_pagination_links() {
        let base = validate_http_url("http://127.0.0.1:8080/opds/").unwrap();
        let xml = r#"<?xml version="1.0" encoding="utf-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <title>本地书库</title>
            <link rel="next" href="page/2" type="application/atom+xml;profile=opds-catalog"/>
            <entry><id>book-1</id><title>三体</title><author><name>刘慈欣</name></author>
              <summary>科幻作品</summary>
              <link rel="subsection" href="series.xml" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
              <link rel="http://opds-spec.org/acquisition" href="../books/three-body.epub" type="application/epub+zip" length="1234"/>
            </entry>
          </feed>"#;
        let feed = parse_atom_feed(xml, &base).unwrap();
        assert_eq!(feed.title, "本地书库");
        assert_eq!(feed.links[0].href, "http://127.0.0.1:8080/opds/page/2");
        assert_eq!(feed.entries.len(), 1);
        assert_eq!(feed.entries[0].title, "三体");
        assert_eq!(feed.entries[0].author, "刘慈欣");
        assert_eq!(feed.entries[0].summary, "科幻作品");
        assert_eq!(
            feed.entries[0].links[1].href,
            "http://127.0.0.1:8080/books/three-body.epub"
        );
        assert_eq!(feed.entries[0].links[1].length, Some(1234));
    }

    #[test]
    fn rejects_unsafe_or_credential_bearing_catalog_urls() {
        assert!(validate_http_url("file:///C:/books").is_err());
        assert!(validate_http_url("javascript:alert(1)").is_err());
        assert!(validate_http_url("https://reader:secret@example.com/opds").is_err());
    }

    #[test]
    fn downloads_atom_acquisition_and_does_not_overwrite_existing_files() {
        use std::io::{Read, Write};
        use std::net::TcpListener;
        use std::time::{SystemTime, UNIX_EPOCH};

        let payload = b"sample ebook bytes";
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0u8; 2048];
            let _ = stream.read(&mut request);
            write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Type: application/epub+zip\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                payload.len()
            ).unwrap();
            stream.write_all(payload).unwrap();
        });

        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let destination =
            std::env::temp_dir().join(format!("hyesread-opds-{}-{nonce}.epub", std::process::id()));
        let runtime = tokio::runtime::Runtime::new().unwrap();
        let saved = runtime
            .block_on(download_book(
                &format!("http://{address}/book.epub"),
                destination.to_str().unwrap(),
            ))
            .unwrap();
        server.join().unwrap();
        assert_eq!(std::fs::read(&saved).unwrap(), payload);

        let duplicate = runtime.block_on(download_book(
            &format!("http://{address}/book.epub"),
            destination.to_str().unwrap(),
        ));
        assert!(duplicate.unwrap_err().contains("已存在"));
        std::fs::remove_file(destination).unwrap();
    }
}
