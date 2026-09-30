{ pkgs }:
let
  lib = pkgs.lib;
  fakeBody = name: ''
    printf '%s\n' ${lib.escapeShellArg name} "$@" >> "$TRACE"
    stage=${if name == "tailscale" then ''"$1"'' else "address"}
    if [ "$CASE" = "$stage-command-failure" ]; then
      echo 'fixture private output' >&2
      exit 7
    fi
    if [ "$CASE" = "$stage-hang" ]; then
      # Regress the too-short fixture deadline with bounded setup latency.
      if [ "$stage" = address ]; then sleep 0.35; fi
      sleep 30 &
      child=$!
      printf '%s\n' "$$" "$child" > "$PIDS"
      # These fixture descendants respond to TERM. TERM-resistant descendant
      # cleanup remains a separate consumer systemd/cgroup acceptance case.
      trap 'wait "$child" 2>/dev/null || :; exit 143' TERM INT
      echo HANG >> "$TRACE"
      wait "$child"
      exit 0
    fi
    ${
      if name == "tailscale" then
        ''
          case "$1" in
            wait) exit 0 ;;
            status) printf '%s\n' "$STATUS_JSON" ;;
            *) exit 8 ;;
          esac
        ''
      else
        ''
          printf '%s\n' "$ADDRESS_JSON"
        ''
    }
  '';
  fakeTailscale = pkgs.writeShellScriptBin "tailscale" (fakeBody "tailscale");
  fakeIp = pkgs.writeShellScriptBin "ip" (fakeBody "ip");
  fixturePkgs = pkgs // {
    iproute2 = fakeIp;
  };
  makeGate =
    args:
    import ../lib/tailscale-ready-gate.nix (
      {
        pkgs = fixturePkgs;
        tailscale = fakeTailscale;
        ipv4 = "100.64.0.1";
        interface = "tailscale0";
      }
      // args
    );
  gate = makeGate { };
  shortGate = makeGate { deadline = "2s"; };
  escapedValue = "quote' $(touch injected); space";
  escapedGate = makeGate {
    ipv4 = escapedValue;
    interface = escapedValue;
  };
  accepts = args: (builtins.tryEval (builtins.deepSeq (makeGate args) true)).success;
in
assert !accepts { ipv4 = ""; };
assert !accepts { interface = ""; };
assert !accepts { ipv4 = null; };
assert !accepts { interface = null; };
assert
  !accepts {
    pkgs = fixturePkgs // {
      stdenv = {
        hostPlatform.isLinux = false;
      };
    };
  };
pkgs.runCommand "tailscale-ready-gate-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.diffutils
      pkgs.jq
    ];
  }
  ''
    set -Eeuo pipefail
    check_started=$(date +%s%N)
    export TRACE="$PWD/trace" PIDS="$PWD/pids" CASE=success
    check_label=setup
    fixture_state() {
      local process_stat
      if [ ! -e "/proc/$1/stat" ]; then
        echo absent
      elif IFS= read -r process_stat 2>/dev/null < "/proc/$1/stat"; then
        process_stat="''${process_stat##*) }"
        echo "''${process_stat%% *}"
      elif [ ! -e "/proc/$1/stat" ]; then
        echo absent
      else
        echo unreadable
      fi
    }
    failure_context() {
      case "$-" in *e*) ;; *) return ;; esac
      echo "FAIL check=$check_label stage=''${stage:-unset} exit=''${actual:-unset} assertion=$BASH_COMMAND" >&2
      for reached in wait status addr HANG; do
        if grep -qFx "$reached" "$TRACE"; then
          echo "fixture reached=$reached" >&2
        fi
      done
      if [ -s "$PIDS" ]; then
        for pid in $(cat "$PIDS"); do
          echo "fixture pid=$pid state=$(fixture_state "$pid")" >&2
        done
      else
        echo 'fixture PIDS absent' >&2
      fi
    }
    trap failure_context ERR
    good_status='{"TUN":true,"BackendState":"Running","TailscaleIPs":["100.64.0.1","fd7a:115c:a1e0::1"]}'
    good_address='[{"ifname":"tailscale0","flags":["POINTOPOINT","UP"],"addr_info":[{"family":"inet","local":"100.64.0.1"}]}]'
    export STATUS_JSON="$good_status" ADDRESS_JSON="$good_address"
    expected_trace() {
      printf '%s\n' tailscale wait --timeout=30s > expected
      if [ "$1" != wait ]; then
        printf '%s\n' tailscale status --json --peers=false >> expected
      fi
      if [ "$1" = address ]; then
        printf '%s\n' ip -j -4 addr show dev tailscale0 >> expected
      fi
    }
    check_case() {
      label=$1 expected_status=$2 stage=$3 diagnostic=$4
      check_label="$label"
      : > "$TRACE"
      set +e
      ${gate} > stdout 2> stderr
      actual=$?
      set -e
      if [ "$expected_status" = success ]; then
        test "$actual" -eq 0
        test ! -s stderr
      else
        test "$actual" -ne 0
        grep -qF "$diagnostic" stderr
      fi
      test ! -s stdout
      if grep -qE 'fixture private output|100\.64\.|tailscale0|BackendState|addr_info' stderr; then
        echo 'fixture details leaked into gate diagnostic' >&2
        exit 1
      fi
      expected_trace "$stage"
      diff -u expected "$TRACE"
      echo "PASS $label"
    }
    check_case success success address unused
    for CASE in wait-command-failure status-command-failure address-command-failure; do
      stage=''${CASE%%-*}
      check_case "$CASE" failure "$stage" "$stage"
    done
    CASE=success
    for STATUS_JSON in \
      '{"TUN":true,"BackendState":"Starting","TailscaleIPs":["100.64.0.1"]}' \
      '{"TUN":false,"BackendState":"Running","TailscaleIPs":["100.64.0.1"]}' \
      '{"TUN":true,"BackendState":"Running","TailscaleIPs":["100.64.0.2"]}' \
      '{"TUN":true,"BackendState":"Running"}' \
      '{"TUN":true,"BackendState":"Running","TailscaleIPs":"100.64.0.1"}' \
      "" 'invalid' "$good_status $good_status"; do
      check_case rejected-status failure status status
    done
    STATUS_JSON="$good_status"
    for ADDRESS_JSON in \
      '[{"ifname":"other0","flags":["UP"],"addr_info":[{"family":"inet","local":"100.64.0.1"}]}]' \
      '[{"ifname":"tailscale0","flags":[],"addr_info":[{"family":"inet","local":"100.64.0.1"}]}]' \
      '[{"ifname":"tailscale0","flags":["UP"],"addr_info":[{"family":"inet","local":"100.64.0.2"}]}]' \
      '[{"ifname":"tailscale0","flags":["UP"],"addr_info":[{"family":"inet6","local":"100.64.0.1"}]}]' \
      '[]' "" 'invalid' "$good_address $good_address"; do
      check_case rejected-address failure address address
    done
    ADDRESS_JSON="$good_address"
    # Shell metacharacters reach native commands and jq as literal arguments.
    export STATUS_JSON=${
      lib.escapeShellArg (
        builtins.toJSON {
          TUN = true;
          BackendState = "Running";
          TailscaleIPs = [ escapedValue ];
        }
      )
    }
    export ADDRESS_JSON=${
      lib.escapeShellArg (
        builtins.toJSON [
          {
            ifname = escapedValue;
            flags = [ "UP" ];
            addr_info = [
              {
                family = "inet";
                local = escapedValue;
              }
            ];
          }
        ]
      )
    }
    : > "$TRACE"
    check_label=literal-arguments
    ${escapedGate} > stdout 2> stderr
    test ! -s stdout
    test ! -s stderr
    test ! -e injected
    printf '%s\n' tailscale wait --timeout=30s tailscale status --json --peers=false ip -j -4 addr show dev \
      ${lib.escapeShellArg escapedValue} > expected
    diff -u expected "$TRACE"
    echo 'PASS literal constructor arguments'
    STATUS_JSON="$good_status" ADDRESS_JSON="$good_address"
    await_hang() {
      for attempt in $(seq 1 200); do
        if grep -q HANG "$TRACE"; then return; fi
        sleep 0.01
      done
      echo 'fixture did not reach hanging command' >&2
      exit 1
    }
    assert_cleanup() {
      test -s "$PIDS"
      grep -qFx HANG "$TRACE"
      for pid in $(cat "$PIDS"); do
        for attempt in $(seq 1 200); do
          state=$(fixture_state "$pid")
          # kill -0 also succeeds for zombies; they have already terminated.
          case "$state" in absent|Z) break ;; esac
          sleep 0.01
        done
        case "$state" in
          absent|Z) ;;
          *)
            echo "fixture descendant still active: pid=$pid state=$state" >&2
            failure_context
            exit 1
            ;;
        esac
        echo "fixture terminated stage=$stage pid=$pid state=$state"
      done
      grep -v '^HANG$' "$TRACE" > actual-trace
      expected_trace "$stage"
      diff -u expected actual-trace
      test ! -s stdout
    }
    # One outer timer covers all stages. Reach the final postcheck with setup
    # margin; cancellation below checks stage ordering at every boundary.
    stage=address
    export CASE="$stage-hang"
    check_label=deadline
    : > "$TRACE"
    rm -f "$PIDS"
    set +e
    ${shortGate} > stdout 2> stderr
    actual=$?
    set -e
    test "$actual" -eq 124
    grep -qF ${lib.escapeShellArg pkgs.runtimeShell} stderr
    if grep -qE 'fixture private output|100\.64\.|tailscale0|BackendState|addr_info|TailscaleIPs' stderr; then
      echo 'fixture details leaked into deadline diagnostic' >&2
      exit 1
    fi
    assert_cleanup
    echo "PASS whole deadline at $stage and TERM-responsive fixture cleanup"
    for stage in wait status address; do
      export CASE="$stage-hang"
      check_label=cancellation
      : > "$TRACE"
      rm -f "$PIDS"
      ${gate} > stdout 2> stderr &
      gate_pid=$!
      await_hang
      for pid in $(cat "$PIDS"); do
        state=$(fixture_state "$pid")
        case "$state" in
          absent|Z|unreadable)
            echo "fixture not active before cancellation: pid=$pid state=$state" >&2
            failure_context
            exit 1
            ;;
        esac
        echo "fixture active stage=$stage pid=$pid state=$state"
      done
      kill -TERM "$gate_pid"
      set +e
      wait "$gate_pid"
      actual=$?
      set -e
      test "$actual" -eq 143
      assert_cleanup
      echo "PASS cancellation at $stage and TERM-responsive fixture cleanup"
    done
    check_finished=$(date +%s%N)
    echo "Contract runtime: $(( (check_finished - check_started) / 1000000 ))ms"
    mkdir -p "$out"
    echo 'Fake CLI behavior and TERM-responsive fixture cleanup only; no real Tailscale or consumer systemd/cgroup acceptance, including TERM-resistant descendant cleanup.' > "$out/scope"
  ''
