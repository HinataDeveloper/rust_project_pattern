use tracing::info;
use tracing_subscriber::EnvFilter;

use std::error::Error;


fn main() -> Result<(), Box<dyn Error>> {
    init_logging();
    println!("\n");

    info!("\nThe End ...");
    Ok(())
}

fn init_logging() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_target(false)
        .init();
}
