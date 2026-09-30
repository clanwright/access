{ pkgs, root }:
pkgs.runCommand "access-release-contract"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.git
      pkgs.openssh
    ];
  }
  ''
    bash ${root}/scripts/test-release.sh
    touch "$out"
  ''
