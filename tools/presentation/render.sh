#!/bin/sh
# QA render: build mockups (once), the deck, then PNG pages. Usage: ./render.sh <work_dir>
set -e
here=$(cd "$(dirname "$0")" && pwd)
work=$1
[ -d "$work/mock" ] || python3 "$here/mockups.py" "$work/mock"
python3 "$here/build_deck.py" "$work/mock"
rm -rf "$work/render" && mkdir -p "$work/render"
cd "$work/render"
soffice --headless --convert-to pdf "$here/../../docs/presentation/alfa-office.pptx" >/dev/null 2>&1
pdftoppm -jpeg -r 100 alfa-office.pdf s
