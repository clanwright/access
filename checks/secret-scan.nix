{ pkgs, root }:
pkgs.runCommand "access-secret-scan-contract"
  {
    nativeBuildInputs = [
      pkgs.gitleaks
      pkgs.python3
    ];
  }
  ''
    python3 ${root}/scripts/test-secret-scan.py
    touch "$out"
  ''
