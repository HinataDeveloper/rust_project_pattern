#!/usr/bin/env zsh

set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "error: commit message is required"
    echo "usage: $0 <commit message>"
    exit 1
fi

# اجرای دقیق اسکریپت با مفسر bash برای حفظ ویژگی‌های bashism و شل داخلی
zsh ./ncopy6.sh run

git add --all

# بررسی اینکه آیا تغییری برای کامیت وجود دارد یا خیر
if git diff --cached --quiet; then
    echo "nothing to commit, working tree clean"
    git status
    exit 0
fi

# کامیت کردن تمام آرگومان‌های ورودی به عنوان یک پیام واحد
git commit -m "$*"
git push origin
git status
