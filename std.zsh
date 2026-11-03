#!/usr/bin/env zsh

# version: Sun Oct 24 2026 

cargo init

cp -r ../project_pattern/template_src .
cp ../project_pattern/dot_gitignore .gitignore

cp ../project_pattern/Cargo.toml .
cp ../project_pattern/clippy.toml .
cp ../project_pattern/rust-toolchain.toml .
cp ../project_pattern/codebook.toml .

cp ../project_pattern/cb.zsh .
cp ../project_pattern/run.zsh .
cp ../project_pattern/ncopy6.zsh .
cp ../project_pattern/grv.zsh .

cp template_src/main.rs src/main.rs
cp template_src/lib.rs src/lib.rs

mkdir -p snapshots

git pull origin

git add --all
git commit -m 'Initial Commit'
git push origin
