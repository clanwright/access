{ pkgs, readme }:
pkgs.runCommand "access-recovery-client-config"
  {
    nativeBuildInputs = [
      pkgs.gawk
      pkgs.gnused
      pkgs.gnugrep
    ];
  }
  ''
    set -eu
    # Parse the documented configuration with the actual pinned OpenSSH client.
    # No credentials, listener, remote connection, or virtual machine is involved.
    awk '/^```sshconfig$/ { active=1; next } active && /^```$/ { exit } active { print }' \
      ${readme} > template
    test -s template
    sed \
      -e 's/<RECOVERY_USER>/access-recovery/g' \
      -e 's/<HOST_KEY_ALIAS>/example-stunnel-ssh-breakglass/g' \
      -e "s|<KNOWN_HOSTS_FILE>|$TMPDIR/recovery kit/known_hosts|g" \
      -e "s|<SSH_PRIVATE_KEY_FILE>|$TMPDIR/recovery kit/identity|g" \
      template > ssh-config
    if grep -E '<[A-Z_]+>' ssh-config; then
      echo 'unresolved recovery configuration placeholder' >&2
      exit 1
    fi
    ${pkgs.openssh}/bin/ssh -G -F ssh-config recovery > effective-config
    require_setting() {
      if ! grep -qxiF "$1" effective-config; then
        echo "missing effective client setting: $1" >&2
        exit 1
      fi
    }
    require_setting 'hostname 127.0.0.1'
    require_setting 'port 14791'
    require_setting 'user access-recovery'
    require_setting 'hostkeyalias example-stunnel-ssh-breakglass'
    require_setting 'stricthostkeychecking true'
    require_setting "userknownhostsfile $TMPDIR/recovery kit/known_hosts"
    require_setting 'globalknownhostsfile /dev/null'
    require_setting 'updatehostkeys false'
    require_setting 'verifyhostkeydns false'
    require_setting 'identitiesonly yes'
    require_setting 'identityagent none'
    require_setting "identityfile $TMPDIR/recovery kit/identity"
    require_setting 'certificatefile none'
    require_setting 'passwordauthentication no'
    require_setting 'kbdinteractiveauthentication no'
    require_setting 'preferredauthentications publickey'
    require_setting 'clearallforwardings yes'
    require_setting 'forwardagent no'
    require_setting 'forwardx11 no'
    require_setting 'controlmaster false'
    require_setting 'controlpersist no'
    if grep -Eq '^(proxycommand|proxyjump|knownhostscommand|controlpath) ' effective-config; then
      echo 'unexpected external command or multiplexing path' >&2
      exit 1
    fi
    # stunnel has no check-only flag. Its parser must reject an absent PSK
    # before opening a listener; never supply a credential to this check.
    awk '/^```ini$/ { active=1; next } active && /^```$/ { exit } active { print }' \
      ${readme} > stunnel-template
    test -s stunnel-template
    sed \
      -e 's/<PUBLIC_IPV4>/127.0.0.1/g' \
      -e 's/<TLS_PORT>/9/g' \
      -e 's/<PSK_IDENTITY>/example/g' \
      -e "s|<PSK_FILE>|$TMPDIR/absent-psk|g" \
      stunnel-template > stunnel-config
    test ! -e "$TMPDIR/absent-psk"
    if grep -E '<[A-Z_]+>' stunnel-config; then
      echo 'unresolved stunnel configuration placeholder' >&2
      exit 1
    fi
    set +e
    ${pkgs.coreutils}/bin/timeout 5 ${pkgs.stunnel}/bin/stunnel stunnel-config > stunnel-rejection 2>&1
    status=$?
    set -e
    if [ "$status" -ne 1 ]; then
      echo "stunnel did not reject missing PSK immediately: status=$status" >&2
      exit 1
    fi
    if ! grep -qF "$TMPDIR/absent-psk: No such file or directory" stunnel-rejection \
      || ! grep -qF 'Failed to read PSK secrets' stunnel-rejection; then
      cat stunnel-rejection >&2
      echo 'stunnel failed for a reason other than the absent PSK' >&2
      exit 1
    fi
    # Execute both pinned tools, without opening any connection.
    ${pkgs.openssh}/bin/ssh -V 2> openssh-version
    ${pkgs.stunnel}/bin/stunnel -version > stunnel-version 2>&1
    mkdir -p "$out"
    cp effective-config openssh-version stunnel-version stunnel-rejection "$out/"
  ''
