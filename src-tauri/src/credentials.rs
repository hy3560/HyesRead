use percent_encoding::percent_decode_str;
use serde::{Deserialize, Serialize};
use url::Url;

#[derive(Serialize, Deserialize)]
struct Login {
    username: String,
    password: String,
}

// Keep the storage boundary separate from URL handling and network requests.
trait Vault {
    fn read(&self, key: &str) -> Result<Option<Login>, String>;
    fn write(&self, key: &str, login: &Login) -> Result<(), String>;
    fn delete(&self, key: &str) -> Result<(), String>;
}

struct SystemVault<'a>(&'a str);

#[cfg(windows)]
static VAULT_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[cfg(windows)]
impl SystemVault<'_> {
    fn entry(&self, key: &str) -> Result<keyring::Entry, String> {
        use sha2::Digest;
        // Windows target names are case insensitive and usernames have a length
        // limit. Hash the complete normalized URL to preserve path identity.
        let id = format!("{:x}", sha2::Sha256::digest(key.as_bytes()));
        keyring::Entry::new(self.0, &id).map_err(|_| "无法打开目录凭据".into())
    }
}

#[cfg(windows)]
impl Vault for SystemVault<'_> {
    fn read(&self, key: &str) -> Result<Option<Login>, String> {
        let _lock = VAULT_LOCK.lock().map_err(|_| "目录凭据状态不可用")?;
        let entry = self.entry(key)?;
        match entry.get_password() {
            Ok(value) => serde_json::from_str(&value)
                .map(Some)
                .map_err(|_| "目录凭据格式无效".into()),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(_) => Err("无法读取系统目录凭据".into()),
        }
    }
    fn write(&self, key: &str, login: &Login) -> Result<(), String> {
        let value = serde_json::to_string(login).map_err(|_| "目录凭据格式无效")?;
        if value.encode_utf16().count() * 2 > 2300 {
            return Err("目录账号或密码过长".into());
        }
        let _lock = VAULT_LOCK.lock().map_err(|_| "目录凭据状态不可用")?;
        self.entry(key)?
            .set_password(&value)
            .map_err(|_| "无法保存系统目录凭据".into())
    }
    fn delete(&self, key: &str) -> Result<(), String> {
        let _lock = VAULT_LOCK.lock().map_err(|_| "目录凭据状态不可用")?;
        match self.entry(key)?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(_) => Err("无法删除系统目录凭据".into()),
        }
    }
}

#[cfg(not(windows))]
impl Vault for SystemVault<'_> {
    fn read(&self, _key: &str) -> Result<Option<Login>, String> {
        let _ = self.0;
        Ok(None)
    }
    fn write(&self, _key: &str, _login: &Login) -> Result<(), String> {
        Err("当前平台暂不支持保存目录凭据".into())
    }
    fn delete(&self, _key: &str) -> Result<(), String> {
        Ok(())
    }
}

fn clean_url(raw: &str) -> Result<(Url, Option<Login>), String> {
    let mut url = Url::parse(raw.trim()).map_err(|_| "目录地址无效")?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return Err("目录只支持 HTTP 或 HTTPS 地址".into());
    }
    let decode = |value: &str| {
        percent_decode_str(value)
            .decode_utf8()
            .map(|value| value.into_owned())
            .map_err(|_| "目录账号信息编码无效".to_string())
    };
    let login = if !url.username().is_empty() || url.password().is_some() {
        Some(Login {
            username: decode(url.username())?,
            password: decode(url.password().unwrap_or(""))?,
        })
    } else {
        None
    };
    url.set_username("").map_err(|_| "目录地址无效")?;
    url.set_password(None).map_err(|_| "目录地址无效")?;
    url.set_fragment(None);
    if url.as_str().len() > 2048 {
        return Err("目录地址过长".into());
    }
    Ok((url, login))
}

fn require_secure(url: &Url) -> Result<(), String> {
    let host = url.host_str().unwrap_or("");
    let loopback = host.eq_ignore_ascii_case("localhost")
        || host
            .trim_matches(['[', ']'])
            .parse::<std::net::IpAddr>()
            .is_ok_and(|address| address.is_loopback());
    if url.scheme() != "https" && !loopback {
        return Err("带账号密码的目录必须使用 HTTPS".into());
    }
    Ok(())
}

fn save_to(
    vault: &impl Vault,
    raw: &str,
    username: Option<String>,
    password: Option<String>,
) -> Result<String, String> {
    let (url, embedded) = clean_url(raw)?;
    let login = match (username, password) {
        (Some(username), Some(password)) => Some(Login { username, password }),
        (None, None) => embedded,
        _ => return Err("请同时填写目录账号和密码".into()),
    };
    if let Some(login) = login {
        if login.username.is_empty() {
            return Err("目录账号不能为空".into());
        }
        require_secure(&url)?;
        vault.write(url.as_str(), &login)?;
    }
    Ok(url.to_string())
}

fn request_from(vault: &impl Vault, raw: &str, source: Option<&str>) -> Result<String, String> {
    let (mut target, embedded) = clean_url(raw)?;
    let login = if let Some(login) = embedded {
        Some(login)
    } else {
        let (source, _) = clean_url(source.unwrap_or(raw))?;
        if source.origin() != target.origin() {
            return Ok(target.to_string());
        }
        vault.read(source.as_str())?
    };
    if let Some(login) = login {
        require_secure(&target)?;
        target
            .set_username(
                &percent_encoding::utf8_percent_encode(
                    &login.username,
                    percent_encoding::NON_ALPHANUMERIC,
                )
                .to_string(),
            )
            .map_err(|_| "目录账号格式无效")?;
        target
            .set_password(Some(
                &percent_encoding::utf8_percent_encode(
                    &login.password,
                    percent_encoding::NON_ALPHANUMERIC,
                )
                .to_string(),
            ))
            .map_err(|_| "目录密码格式无效")?;
    }
    Ok(target.to_string())
}

pub fn save(
    service: &str,
    raw: &str,
    username: Option<String>,
    password: Option<String>,
) -> Result<String, String> {
    save_to(&SystemVault(service), raw, username, password)
}
pub fn request(service: &str, raw: &str, source: Option<&str>) -> Result<String, String> {
    request_from(&SystemVault(service), raw, source)
}
pub fn request_with_login(
    service: &str,
    raw: &str,
    source: Option<&str>,
    username: Option<String>,
    password: Option<String>,
) -> Result<String, String> {
    match (username, password) {
        (None, None) => request(service, raw, source),
        (Some(username), Some(password)) if !username.is_empty() => {
            let (mut url, _) = clean_url(raw)?;
            require_secure(&url)?;
            url.set_username(
                &percent_encoding::utf8_percent_encode(
                    &username,
                    percent_encoding::NON_ALPHANUMERIC,
                )
                .to_string(),
            )
            .map_err(|_| "目录账号格式无效")?;
            url.set_password(Some(
                &percent_encoding::utf8_percent_encode(
                    &password,
                    percent_encoding::NON_ALPHANUMERIC,
                )
                .to_string(),
            ))
            .map_err(|_| "目录密码格式无效")?;
            Ok(url.to_string())
        }
        _ => Err("请填写目录账号和密码".into()),
    }
}
pub fn delete(service: &str, raw: &str) -> Result<(), String> {
    let (url, _) = clean_url(raw)?;
    SystemVault(service).delete(url.as_str())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::HashMap;
    #[derive(Default)]
    struct FakeVault(RefCell<HashMap<String, String>>);
    impl Vault for FakeVault {
        fn read(&self, key: &str) -> Result<Option<Login>, String> {
            Ok(self
                .0
                .borrow()
                .get(key)
                .map(|value| serde_json::from_str(value).unwrap()))
        }
        fn write(&self, key: &str, login: &Login) -> Result<(), String> {
            self.0
                .borrow_mut()
                .insert(key.into(), serde_json::to_string(login).unwrap());
            Ok(())
        }
        fn delete(&self, key: &str) -> Result<(), String> {
            self.0.borrow_mut().remove(key);
            Ok(())
        }
    }
    #[test]
    fn migrates_embedded_credentials_and_only_reuses_them_on_the_same_origin() {
        let vault = FakeVault::default();
        let source = save_to(
            &vault,
            "https://user%40x:pa%3Ass@example.com/opds#ignored",
            None,
            None,
        )
        .unwrap();
        assert_eq!(source, "https://example.com/opds");
        let request = request_from(&vault, "https://example.com/next", Some(&source)).unwrap();
        let parsed = Url::parse(&request).unwrap();
        assert_eq!(
            percent_decode_str(parsed.username()).decode_utf8().unwrap(),
            "user@x"
        );
        assert_eq!(
            percent_decode_str(parsed.password().unwrap())
                .decode_utf8()
                .unwrap(),
            "pa:ss"
        );
        for target in [
            "https://other.example/next",
            "http://example.com/next",
            "https://example.com:8443/next",
        ] {
            assert_eq!(
                request_from(&vault, target, Some(&source)).unwrap(),
                Url::parse(target).unwrap().to_string()
            );
        }
        vault.delete(&source).unwrap();
        assert_eq!(request_from(&vault, &source, None).unwrap(), source);
    }
    #[test]
    fn preserves_literal_percent_sequences_and_unicode_login_values() {
        let vault = FakeVault::default();
        let source = "https://example.com/opds";
        save_to(
            &vault,
            source,
            Some("读者%40x".into()),
            Some("pa%3Ass:/@".into()),
        )
        .unwrap();
        for request in [
            request_from(&vault, source, None).unwrap(),
            request_with_login(
                "unused",
                source,
                None,
                Some("读者%40x".into()),
                Some("pa%3Ass:/@".into()),
            )
            .unwrap(),
        ] {
            let url = Url::parse(&request).unwrap();
            assert_eq!(
                percent_decode_str(url.username()).decode_utf8().unwrap(),
                "读者%40x"
            );
            assert_eq!(
                percent_decode_str(url.password().unwrap())
                    .decode_utf8()
                    .unwrap(),
                "pa%3Ass:/@"
            );
        }
    }
    #[test]
    fn refuses_insecure_or_invalid_credentials_without_persisting_them() {
        let vault = FakeVault::default();
        for url in [
            "http://reader:secret@example.com/opds",
            "file:///books",
            "https://:secret@example.com/opds",
        ] {
            assert!(save_to(&vault, url, None, None).is_err());
        }
        assert!(vault.0.borrow().is_empty());
        assert!(save_to(
            &vault,
            "http://127.0.0.1:9999/opds",
            Some("reader".into()),
            Some("secret".into())
        )
        .is_ok());
    }
    #[cfg(windows)]
    #[test]
    fn windows_vault_round_trip_and_deletion() {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let service = format!("HyesRead.acceptance.{}.{nonce}", std::process::id());
        let vault = SystemVault(&service);
        let source = "https://hyesread-test.invalid/opds";
        let upper_source = "https://hyesread-test.invalid/OPDS";
        let long_source = format!(
            "https://hyesread-test.invalid/opds?query={}",
            "x".repeat(800)
        );
        let result = (|| -> Result<(), String> {
            save_to(
                &vault,
                source,
                Some("synthetic-user".into()),
                Some("synthetic-password".into()),
            )?;
            let login = vault.read(source)?.ok_or("Missing test credential")?;
            if login.username != "synthetic-user" || login.password != "synthetic-password" {
                return Err("Credential round trip changed the login".into());
            }
            save_to(
                &vault,
                upper_source,
                Some("different-user".into()),
                Some("different-password".into()),
            )?;
            if vault
                .read(source)?
                .ok_or("Missing original credential")?
                .username
                != "synthetic-user"
            {
                return Err("Case-sensitive catalog paths shared a credential".into());
            }
            if vault
                .read(upper_source)?
                .ok_or("Missing uppercase credential")?
                .username
                != "different-user"
            {
                return Err("Uppercase catalog credential was not preserved".into());
            }
            save_to(
                &vault,
                &long_source,
                Some("long-url-user".into()),
                Some("synthetic-password".into()),
            )?;
            if vault
                .read(&long_source)?
                .ok_or("Missing long-URL credential")?
                .username
                != "long-url-user"
            {
                return Err("Long catalog URL did not round trip".into());
            }
            if vault
                .write(
                    source,
                    &Login {
                        username: "synthetic-user".into(),
                        password: "x".repeat(1400),
                    },
                )
                .is_ok()
            {
                return Err("Oversized credential was accepted".into());
            }
            if vault
                .read(source)?
                .ok_or("Missing original credential")?
                .password
                != "synthetic-password"
            {
                return Err("Rejected credential replaced the original password".into());
            }
            Ok(())
        })();
        vault.delete(source).unwrap();
        vault.delete(upper_source).unwrap();
        vault.delete(&long_source).unwrap();
        result.unwrap();
        assert!(vault.read(source).unwrap().is_none());
    }
}
