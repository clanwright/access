{ pkgs, root }:
pkgs.runCommand "access-verification-contract"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
    ];
  }
  ''
    bash ${root}/scripts/test-verification.sh
    touch "$out"
  ''
