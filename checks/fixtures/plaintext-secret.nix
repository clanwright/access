{
  candidate ? {
    keySecretValue = true;
  },
}:
let
  forbiddenInputs = [
    "authKeyValue"
    "credential"
    "hmacSecretValue"
    "keySecretValue"
    "password"
    "secretValue"
    "token"
  ];
in
if builtins.any (name: builtins.hasAttr name candidate) forbiddenInputs then
  throw "secret values are not an Access input"
else
  candidate
