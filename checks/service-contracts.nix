{
  pkgs,
  self,
  system,
}:
pkgs.runCommand "access-service-contracts"
  {
    verifiedChecks = [
      self.checks.${system}.tailscale-admin-contract
      self.checks.${system}.stunnel-ssh-breakglass-contract
    ];
  }
  ''
    for check in $verifiedChecks; do
      test -e "$check"
    done
    touch "$out"
  ''
