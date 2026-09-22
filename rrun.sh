#!/bin/env zsh

clear
cargo check && cargo clippy && cargo run
