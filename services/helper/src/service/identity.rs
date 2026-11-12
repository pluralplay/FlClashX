use std::path::Path;

use once_cell::sync::Lazy;

const STABLE_HELPER: &str = "FlClashXHelperService";
const PRE_HELPER: &str = "FlClashXPreHelperService";

/// A pre-release ships this binary as `FlClashXPreHelperService`, and every
/// name the Helper registers follows from that, so a stable and a pre-release
/// install keep their own service, port key, unit and socket.
static PRE: Lazy<bool> = Lazy::new(|| {
    std::env::current_exe()
        .map(|path| is_pre_helper(&path))
        .unwrap_or(false)
});

pub fn is_pre_helper(executable: &Path) -> bool {
    executable
        .file_stem()
        .and_then(|stem| stem.to_str())
        .is_some_and(|stem| stem.eq_ignore_ascii_case(PRE_HELPER))
}

pub fn helper_name() -> &'static str {
    helper_name_for(*PRE)
}

pub fn helper_name_for(pre: bool) -> &'static str {
    if pre {
        PRE_HELPER
    } else {
        STABLE_HELPER
    }
}

#[cfg(any(target_os = "linux", test))]
pub fn linux_service_for(pre: bool) -> &'static str {
    if pre {
        "flclashx-pre-helper"
    } else {
        "flclashx-helper"
    }
}

#[cfg(any(target_os = "linux", test))]
pub fn linux_runtime_dir_for(pre: bool) -> &'static str {
    if pre {
        "flclashx-pre"
    } else {
        "flclashx"
    }
}

#[cfg(target_os = "linux")]
pub fn is_pre() -> bool {
    *PRE
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_follow_the_helper_binary() {
        assert!(is_pre_helper(Path::new("FlClashXPreHelperService.exe")));
        assert!(is_pre_helper(Path::new(
            "/opt/FlClashXPre/FlClashXPreHelperService"
        )));
        assert!(!is_pre_helper(Path::new(
            "/opt/FlClashX/FlClashXHelperService"
        )));
        assert_eq!(helper_name_for(true), "FlClashXPreHelperService");
        assert_eq!(helper_name_for(false), "FlClashXHelperService");
        assert_eq!(linux_service_for(true), "flclashx-pre-helper");
        assert_eq!(linux_runtime_dir_for(false), "flclashx");
    }
}
