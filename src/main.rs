use clap::Parser;

use crate::cli::Args;

mod activity;
mod cli;

fn main() {
    let args = Args::parse();
}
