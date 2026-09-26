use std::path::Path;

#[derive(Debug, Default)]
pub struct Snapshot {
    pub path: Option<String>,
    pub language: Option<String>,
}

#[derive(Debug, PartialEq, Eq)]
pub struct ActivityText {
    pub details: String,
    pub state: Option<String>,
}

pub fn format(snapshot: &Snapshot, hide_filename: bool, hide_project: bool) -> ActivityText {
    let path = snapshot
        .path
        .as_deref()
        .filter(|path| !path.is_empty())
        .map(Path::new);

    let details = if hide_filename {
        "Editing in Helix".to_owned()
    } else {
        path.and_then(file_name)
            .map(|name| label(&format!("Editing {name}")))
            .unwrap_or_else(|| "Editing an unnamed buffer".to_owned())
    };

    let project = if hide_project {
        None
    } else {
        path.and_then(project_name)
    };
    let language = snapshot
        .language
        .as_deref()
        .map(label)
        .filter(|name| !name.is_empty());
    let state = [project, language]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" · ");

    ActivityText {
        details,
        state: (!state.is_empty()).then(|| label(&state)),
    }
}

fn project_name(path: &Path) -> Option<String> {
    let parent = path.parent()?;

    parent
        .ancestors()
        .find(|directory| directory.join(".git").exists())
        .and_then(file_name)
        .or_else(|| file_name(parent))
}

fn file_name(path: &Path) -> Option<String> {
    path.file_name()
        .map(|name| label(&name.to_string_lossy()))
        .filter(|name| !name.is_empty())
}

fn label(value: &str) -> String {
    let mut result = String::new();
    for character in value.chars() {
        let character = if character.is_control() {
            ' '
        } else {
            character
        };
        if result.len() + character.len_utf8() > 128 {
            break;
        }
        result.push(character);
    }
    result.trim().to_owned()
}
