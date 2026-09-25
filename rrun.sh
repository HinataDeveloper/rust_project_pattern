#!/usr/bin/env zsh

clear
cargo check && cargo clippy && cargo build && cargo run
