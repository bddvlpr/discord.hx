use clap::Parser;

#[derive(Parser, Debug)]
#[command(version, about)]
pub struct Args {
    #[arg(long, value_parser = parse_application_id)]
    pub application_id: u64,

    #[arg(long)]
    pub hide_filename: bool,

    #[arg(long)]
    pub hide_project: bool,
}

fn parse_application_id(value: &str) -> Result<u64, String> {
    if value.is_empty() || value.len() > 20 {
        return Err("application id is invalid".into());
    }

    value
        .parse::<u64>()
        .ok()
        .filter(|id| *id != 0)
        .ok_or_else(|| "application id must be nonzero".into())
}
