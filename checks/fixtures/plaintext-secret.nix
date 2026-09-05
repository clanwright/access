# A boolean marks an invalid setting name; this fixture contains no secret value.
# The real role interface, rather than a parallel deny-list, decides validity.
{
  lib,
  interface,
  candidate ? { },
}:
builtins.deepSeq
  (lib.evalModules {
    modules = [
      interface
      { config = candidate; }
    ];
  }).config
  true
