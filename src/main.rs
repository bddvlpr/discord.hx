use std::{
    error::Error,
    io,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use clap::Parser;
use discord_presence::Client;

use crate::{activity::Snapshot, cli::Args};

mod activity;
mod cli;
mod protocol;

fn main() {
    if let Err(error) = run() {
        eprintln!("discord-hx: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn Error>> {
    let args = Args::parse();
    let started = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let mut client = Client::with_error_config(args.application_id, Duration::from_secs(1), None);
    client.start();

    let mut input = io::stdin().lock();
    let mut output = io::stdout().lock();
    let result = (|| -> io::Result<()> {
        loop {
            let operation = match protocol::read_line(&mut input)? {
                protocol::Line::Eof => return Ok(()),
                protocol::Line::TooLong => {
                    protocol::reply(&mut output, Err("request exceeds 16 KiB"))?;
                    continue;
                }
                protocol::Line::Data(line) => match protocol::parse(&line) {
                    Ok(operation) => operation,
                    Err(error) => {
                        protocol::reply(&mut output, Err(&error))?;
                        continue;
                    }
                },
            };
            match operation {
                protocol::Operation::Update(snapshot) => {
                    queue_update(&mut client, snapshot, &args, started);
                    protocol::reply(&mut output, Ok(()))?;
                }
                protocol::Operation::Shutdown => {
                    protocol::reply(&mut output, Ok(()))?;
                    return Ok(());
                }
            }
        }
    })();

    let shutdown = client.shutdown();
    result?;
    shutdown?;
    Ok(())
}

fn queue_update(client: &mut Client, snapshot: Snapshot, args: &Args, started: u64) {
    let text = activity::format(&snapshot, args.hide_filename, args.hide_project);
    client.queue_activity(move |mut presence| {
        presence = presence
            .details(text.details)
            .timestamps(|timestamps| timestamps.start(started));
        if let Some(state) = text.state {
            presence = presence.state(state);
        }
        presence
    });
}
