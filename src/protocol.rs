use std::io::{self, BufRead, Write};

use serde::Deserialize;
use serde_json::json;

use crate::activity::Snapshot;

const MAX_LINE: usize = 16 * 1024;

pub enum Line {
    Eof,
    Data(Vec<u8>),
    TooLong,
}

pub enum Operation {
    Update(Snapshot),
    Shutdown,
}

pub fn read_line(input: &mut impl BufRead) -> io::Result<Line> {
    let mut line = Vec::new();
    let mut too_long = false;
    loop {
        let available = input.fill_buf()?;
        if available.is_empty() {
            return if line.is_empty() && !too_long {
                Ok(Line::Eof)
            } else if too_long {
                Ok(Line::TooLong)
            } else {
                Ok(Line::Data(line))
            };
        }
        let newline = available.iter().position(|byte| *byte == b'\n');
        let length = newline.map_or(available.len(), |index| index + 1);
        if !too_long {
            if line.len() + length <= MAX_LINE {
                line.extend_from_slice(&available[..length]);
            } else {
                too_long = true;
                line.clear();
            }
        }
        input.consume(length);
        if newline.is_some() {
            return Ok(if too_long {
                Line::TooLong
            } else {
                Line::Data(line)
            });
        }
    }
}

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
enum Request {
    Update {
        v: u32,
        path: Option<String>,
        language: Option<String>,
    },
    Shutdown {
        v: u32,
    },
}

pub fn parse(line: &[u8]) -> Result<Operation, String> {
    match serde_json::from_slice::<Request>(line) {
        Ok(Request::Update {
            v: 1,
            path,
            language,
        }) => Ok(Operation::Update(Snapshot { path, language })),
        Ok(Request::Shutdown { v: 1 }) => Ok(Operation::Shutdown),
        Ok(_) => Err("unsupported protocol version".into()),
        Err(error) => Err(format!("invalid request: {error}")),
    }
}

pub fn reply(output: &mut impl Write, result: Result<(), &str>) -> io::Result<()> {
    match result {
        Ok(()) => serde_json::to_writer(&mut *output, &json!({ "v": 1, "ok": true }))?,
        Err(error) => serde_json::to_writer(
            &mut *output,
            &json!({ "v": 1, "ok": false, "error": error }),
        )?,
    }
    output.write_all(b"\n")?;
    output.flush()
}
