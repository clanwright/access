{ lib }:
name: checks:
let
  failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
if failed == [ ] then true else throw "${name} failed: ${lib.concatStringsSep ", " failed}"
