#!/usr/bin/env bash
# Use only the existing public release key to check the full-line exemption.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
directory=$(mktemp -d)
trap 'rm -rf "$directory"' EXIT
mkdir "$directory/source"
awk '!/^#/ && NF { print $3, $4; exit }' "$root/.github/release-signers" > "$directory/public-key"
fingerprint=$(ssh-keygen -lf "$directory/public-key" | awk '{print $2}')
line="Good \"git\" signature for access-release with ED25519 key $fingerprint"
scan() {
  gitleaks dir "$directory/source" --config "$root/.gitleaks.toml" \
    --no-banner --redact --report-format json --report-path "$directory/report.json"
}
printf '%s\n' "$line" > "$directory/source/verification.log"
scan
jq -e 'length == 0' "$directory/report.json"
# The scanner's line target differs after an earlier newline in the fragment.
printf 'before\n%s\nafter\n' "$line" > "$directory/source/verification.log"
scan
jq -e 'length == 0' "$directory/report.json"
for changed in "unexpected: $line" "$line unexpected"; do
  printf '%s\n' "$changed" > "$directory/source/verification.log"
  status=0
  scan || status=$?
  test "$status" -eq 1
  jq -e 'length == 1 and .[0].RuleID == "generic-api-key" and .[0].Secret == "REDACTED"' "$directory/report.json"
  # A correct neighboring message must never exempt a malformed physical line.
  printf 'before\n%s\n%s\nafter\n' "$line" "$changed" > "$directory/source/verification.log"
  status=0
  scan || status=$?
  test "$status" -eq 1
  jq -e 'length == 1 and .[0].RuleID == "generic-api-key" and .[0].StartLine == 3 and .[0].EndLine == 3 and .[0].Secret == "REDACTED"' "$directory/report.json"
  printf 'before\n%s\n%s\nafter\n' "$changed" "$line" > "$directory/source/verification.log"
  status=0
  scan || status=$?
  test "$status" -eq 1
  jq -e 'length == 1 and .[0].RuleID == "generic-api-key" and .[0].StartLine == 2 and .[0].EndLine == 2 and .[0].Secret == "REDACTED"' "$directory/report.json"
done
