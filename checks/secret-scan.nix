{ pkgs, root }:
pkgs.runCommand "access-secret-scan-contract"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.gitleaks
      pkgs.openssh
      pkgs.jq
    ];
  }
  ''
    bash ${root}/scripts/test-secret-scan.sh
    touch "$out"
  ''
