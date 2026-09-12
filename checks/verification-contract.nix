{ pkgs, root }:
pkgs.runCommand "access-verification-contract"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
      pkgs.python3
    ];
  }
  ''
    python3 ${root}/scripts/test-verification.py
    touch "$out"
  ''
