#!/usr/bin/env bash
# Rule engine evaluator: processes unified decision table from lanekeep.json .rules[]
# First-match-wins, replaces hardblock + codediff when rules are present.

RULES_PASSED=true
RULES_REASON=""
RULES_DECISION="allow"
RULES_COMPLIANCE="[]"
RULES_COMPLIANCE_TAGS="[]"
RULES_INTENT=""

# Verify Ed25519 signature on a Pro compliance pack's rules file.
# Free/community packs pass without check. Pro packs require valid signature.
# Returns: 0 = valid (or free), 1 = invalid/tampered, 2 = unsigned or no pubkey
verify_pack_rules() {
  local rules_file="$1"
  local pubkey_pem="${2:-}"

  [ -f "$rules_file" ] || return 2

  local content
  content=$(cat "$rules_file") || return 2

  # Free/community packs don't need signatures
  local tier
  tier=$(printf '%s' "$content" | jq -r '.tier // "free"' 2>/dev/null) || tier="free"
  case "$tier" in
    free|community) return 0 ;;
  esac

  # Resolve pubkey: argument > config > default path
  if [ -z "$pubkey_pem" ]; then
    pubkey_pem=$(jq -r '.signing.pack_pubkey_path // .signing.pubkey_path // ""' \
      "${LANEKEEP_CONFIG_FILE:-/dev/null}" 2>/dev/null) || pubkey_pem=""
    [ -n "$pubkey_pem" ] || pubkey_pem="${LANEKEEP_DIR:-}/keys/pack-signing.pub"
  fi

  # Source signing module if not already loaded
  if ! command -v verify_inline_sig >/dev/null 2>&1; then
    [ -f "${LANEKEEP_DIR:-}/lib/signing.sh" ] || return 2
    source "${LANEKEEP_DIR}/lib/signing.sh"
  fi

  verify_inline_sig "$content" "$pubkey_pem"
}

rules_enabled() {
  local config="$LANEKEEP_CONFIG_FILE"
  [ -f "$config" ] || return 1
  local count
  count=$(jq '.rules | length // 0' "$config" 2>/dev/null) || return 1
  [ "$count" -gt 0 ]
}

validate_patterns() {
  local config="${1:-$LANEKEEP_CONFIG_FILE}"
  [ -f "$config" ] || return 0
  local issues
  issues=$(timeout 3 jq -r '
    def safe_test(pat; flags): try test(pat; flags) catch "invalid";

    # Collect all regex patterns from rules and policies
    [
      (.rules // [] | .[] | .match // {} |
        ([.pattern, .target, .tool] | map(select(. != null and . != "")) | .[])
      ),
      (.policies // {} | to_entries[] | .value |
        ((.denied // []) + (.allowed // []) | .[])
      )
    ] |
    map(select(. != null and . != "")) | unique | .[] |
    . as $pat |
    # Test 1: is the regex valid?
    if ("" | safe_test($pat; "i")) == "invalid" then
      "WARN: invalid regex: " + $pat
    # Test 2: nested quantifiers (ReDoS indicator)
    elif ($pat | test("\\([^)]*[+*]\\)[+*?]")) then
      "WARN: nested quantifiers (ReDoS risk): " + $pat
    else empty end
  ' "$config" 2>/dev/null) || true
  if [ -n "$issues" ]; then
    printf '%s\n' "$issues" | while IFS= read -r line; do
      echo "[LaneKeep] $line" >&2
    done
    return 1
  fi
  return 0
}

policies_check() {
  local tool_name="$1"
  local tool_input="$2"
  local config="$LANEKEEP_CONFIG_FILE"

  # Skip if no policies section exists
  local has_policies
  has_policies=$(jq 'has("policies") and (.policies | length > 0)' "$config" 2>/dev/null) || return 0
  [ "$has_policies" = "true" ] || return 0

  local result
  result=$(timeout 5 jq -c --arg tool "$tool_name" --arg input "$tool_input" '
    # VULN-07: safe_test wraps test() in try-catch to prevent regex injection crashes
    def safe_test(pat; flags): try test(pat; flags) catch false;
    def safe_test(pat): try test(pat) catch false;

    def is_glob:
      (test("\\\\") | not) and test("[*?]");

    def glob_to_regex:
      gsub("\\?"; "\u0002") |
      gsub("\\*\\*"; "\u0001") |
      gsub("\\."; "\\.") |
      gsub("\\+"; "\\+") | gsub("\\^"; "\\^") | gsub("\\$"; "\\$") |
      gsub("\\{"; "\\{") | gsub("\\}"; "\\}") |
      gsub("\\("; "\\(") | gsub("\\)"; "\\)") |
      gsub("\\|"; "\\|") | gsub("\\["; "\\[") | gsub("\\]"; "\\]") |
      gsub("\\*"; "[^/]*") |
      gsub("\u0001/"; "(.*/)?") |
      gsub("\u0001"; ".*") |
      gsub("\u0002"; "[^/]");

    def glob_anchored:
      . as $orig | glob_to_regex |
      if ($orig | contains("/")) then "^" + . + "$"
      else "(^|/)" + . + "$" end;

    def path_match($path):
      . as $pat |
      if ($pat | is_glob) then ($pat | glob_anchored as $re | $path | safe_test($re; "i"))
      else ($path | safe_test($pat; "i")) end;

    .policies as $raw_p |

    # Phase 0: Auto-migrate old format to symmetric model
    ($raw_p |
      if has("allowed_extensions") or has("allowed_repos") or has("denied_domains") or has("denied_ips") then
        (if has("allowed_extensions") then {extensions: {default: "deny", allowed: .allowed_extensions, denied: []}} else {} end) +
        (if has("allowed_repos") then {repos: {default: "deny", allowed: .allowed_repos, denied: []}} else {} end) +
        (if has("denied_domains") then {domains: {default: "allow", allowed: [], denied: .denied_domains}} else {} end) +
        (if has("denied_ips") then {ips: {default: "allow", allowed: [], denied: .denied_ips}} else {} end)
      else . end
    ) as $p |

    ($input | ascii_downcase) as $lower_input |
    ($tool | ascii_downcase) as $lower_tool |

    # Extract file extension from tool_input (for Write/Edit/Read)
    (try ($input | fromjson | .file_path // "") catch "") as $file_path |
    ($file_path | if . != "" then (. | split(".") | if length > 1 then "." + last else "" end) else "" end) as $ext |

    # Extract command string from tool_input (for Bash)
    (try ($input | fromjson | .command // "") catch "") as $cmd_str |

    # Quote-stripped command for evasion detection
    ($cmd_str | gsub("[\u0027\u0022]"; "")) as $cmd_clean |

    # --- Network surface: tool-type-aware string for network policies ---
    (if $lower_tool == "bash" then $cmd_str
     elif ($lower_tool | test("^(write|edit|read)$")) then $file_path
     else $lower_input end) as $network_surface |

    # --- Extract domains from URLs + bare domain patterns ---
    (if $network_surface == "" then []
     else
       (try ([($network_surface | match("(https?|ftp|ssh|telnet)://([^/:\"\\s]+)"; "gi"))] | map(.captures[1].string)) catch []) +
       (try ([($network_surface | match("\\b([a-zA-Z0-9][-a-zA-Z0-9]*\\.(com|net|org|io|dev|co|edu|gov|mil|int|info|biz|xyz|app|cloud|ai))\\b"; "gi"))] | map(.captures[0].string)) catch [])
       | unique | map(ascii_downcase)
     end) as $extracted_domains |

    # --- Extract IPs (N.N.N.N) from network surface ---
    (if $network_surface == "" then []
     else try ([($network_surface | match("\\b([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})\\b"; "g"))] | map(.captures[0].string) | unique) catch []
     end) as $extracted_ips |

    # --- Extract ports from URL-like patterns ---
    (if $network_surface == "" then []
     else
       (try ([($network_surface | match("://[^/:]+:([0-9]+)"; "g"))] | map(.captures[0].string)) catch []) +
       (try ([($network_surface | match("@[^/:]+:([0-9]+)"; "g"))] | map(.captures[0].string)) catch [])
       | unique
     end) as $extracted_ports |

    # --- Extract protocol schemes ---
    (if $network_surface == "" then []
     else try ([($network_surface | match("([a-zA-Z][a-zA-Z0-9+.-]*)://"; "g"))] | map(.captures[0].string | ascii_downcase) | unique) catch []
     end) as $extracted_protocols |

    # --- Extract git branch ref (positional parsing) ---
    (if ($lower_tool == "bash") and ($cmd_str | test("git\\s+(push|checkout|switch|merge|branch|rebase)"; "i")) then
      if ($cmd_str | test("git\\s+push"; "i")) then
        try ([($cmd_str | match("git\\s+push\\s+(.+)$"; "i") | .captures[0].string) |
          split(" ") | map(select(length > 0)) | .[] | select(test("^-") | not)] |
          if length >= 2 then
            if (.[1] | contains(":")) then (.[1] | split(":") | last)
            else .[1] end
          else null end) catch null
      elif ($cmd_str | test("git\\s+(checkout|switch|merge|rebase)"; "i")) then
        try ([($cmd_str | match("git\\s+(?:checkout|switch|merge|rebase)\\s+(.+)$"; "i") | .captures[0].string) |
          split(" ") | map(select(length > 0)) | .[] | select(test("^-") | not)] |
          if length >= 1 then last else null end) catch null
      elif ($cmd_str | test("git\\s+branch"; "i")) then
        try ([($cmd_str | match("git\\s+branch\\s+(.+)$"; "i") | .captures[0].string) |
          split(" ") | map(select(length > 0)) | .[] | select(test("^-") | not)] |
          if length >= 1 then last else null end) catch null
      else null end
    else null end) as $extracted_branch |

    # Phase 1: Evaluate each category — denied[] wins > allowed[] > default
    # Each category can be disabled with "enabled": false — skip silently

    # tools: all tools, regex match on tool name
    (if ($p | has("tools")) and (if ($p.tools | has("enabled")) then $p.tools.enabled else true end) then
      ($p.tools) as $cat |
      ($cat.default // "allow") as $def |
      ($cat.denied // [] | map(select(. as $pat | $tool | safe_test($pat; "i"))) | first // null) as $matched_denied |
      if $matched_denied != null then
        {ok: false, reason: ("[LaneKeep] DENIED by Policy (tools)\nTool \"" + $tool + "\" is in the denied list"), policy: "tools"}
      elif ($cat.allowed // [] | any(. as $pat | $tool | safe_test($pat; "i"))) then
        {ok: true}
      elif $def == "deny" then
        {ok: false, reason: ("[LaneKeep] DENIED by Policy (tools)\nTool \"" + $tool + "\" is not in the allowed list"), policy: "tools"}
      else {ok: true} end
    else {ok: true} end) |

    # extensions: Write/Edit/Read only, exact string match
    if .ok then
    (if ($p | has("extensions")) and (if ($p.extensions | has("enabled")) then $p.extensions.enabled else true end) and ($lower_tool | test("^(write|edit|read)$")) and $ext != "" then
      ($p.extensions) as $cat |
      ($cat.default // "allow") as $def |
      if ($cat.denied // [] | any(. == $ext)) then
        {ok: false, reason: ("[LaneKeep] DENIED by Policy (extensions)\nFile extension \"" + $ext + "\" is in the denied list"), policy: "extensions"}
      elif ($cat.allowed // [] | any(. == $ext)) then
        {ok: true}
      elif $def == "deny" then
        {ok: false, reason: ("[LaneKeep] DENIED by Policy (extensions)\nFile extension \"" + $ext + "\" is not in the allowed list"), policy: "extensions"}
      else {ok: true} end
    else {ok: true} end)
    else . end |

    # paths: Write/Edit/Read only, regex match on file_path
    if .ok then
      if ($p | has("paths")) and (if ($p.paths | has("enabled")) then $p.paths.enabled else true end) and ($lower_tool | test("^(write|edit|read)$")) and $file_path != "" then
        ($p.paths) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat | $pat | path_match($file_path))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (paths)\nPath \"" + $file_path + "\" is in the denied list"), policy: "paths"}
        elif ($cat.allowed // [] | any(. as $pat | $pat | path_match($file_path))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (paths)\nPath \"" + $file_path + "\" is not in the allowed list"), policy: "paths"}
        else {ok: true} end
      else . end
    else . end |

    # commands: Bash only, regex match on command string (+ quote-stripped variant)
    if .ok then
      if ($p | has("commands")) and (if ($p.commands | has("enabled")) then $p.commands.enabled else true end) and ($lower_tool == "bash") and $cmd_str != "" then
        ($p.commands) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat |
          ($cmd_str | safe_test($pat; "i")) or ($cmd_clean | safe_test($pat; "i"))
        )) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (commands)\nCommand is in the denied list"), policy: "commands"}
        elif ($cat.allowed // [] | any(. as $pat |
          ($cmd_str | safe_test($pat; "i")) or ($cmd_clean | safe_test($pat; "i"))
        )) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (commands)\nCommand is not in the allowed list"), policy: "commands"}
        else {ok: true} end
      else . end
    else . end |

    # arguments: Bash only, regex match on command string flags (+ quote-stripped variant)
    if .ok then
      if ($p | has("arguments")) and (if ($p.arguments | has("enabled")) then $p.arguments.enabled else true end) and ($lower_tool == "bash") and $cmd_str != "" then
        ($p.arguments) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat |
          ($cmd_str | safe_test($pat; "i")) or ($cmd_clean | safe_test($pat; "i"))
        )) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (arguments)\nArgument pattern is in the denied list"), policy: "arguments"}
        elif ($cat.allowed // [] | any(. as $pat |
          ($cmd_str | safe_test($pat; "i")) or ($cmd_clean | safe_test($pat; "i"))
        )) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (arguments)\nArgument pattern is not in the allowed list"), policy: "arguments"}
        else {ok: true} end
      else . end
    else . end |

    # repos: Bash only, git commands, regex match
    if .ok then
      if ($p | has("repos")) and (if ($p.repos | has("enabled")) then $p.repos.enabled else true end) and ($lower_tool == "bash") and ($lower_input | test("git\\s+(clone|push|pull|fetch|remote)")) then
        ($p.repos) as $cat |
        ($cat.default // "allow") as $def |
        if ($cat.denied // [] | any(. as $pat | $lower_input | safe_test($pat; "i"))) then
          {ok: false, reason: "[LaneKeep] DENIED by Policy (repos)\nRepository is in the denied list", policy: "repos"}
        elif ($cat.allowed // [] | any(. as $pat | $lower_input | safe_test($pat; "i"))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: "[LaneKeep] DENIED by Policy (repos)\nRepository not in the allowed list", policy: "repos"}
        else {ok: true} end
      else . end
    else . end |

    # branches: Bash only, git branch-related commands, regex match on extracted branch
    if .ok then
      if ($p | has("branches")) and (if ($p.branches | has("enabled")) then $p.branches.enabled else true end) and ($lower_tool == "bash") and ($extracted_branch != null) then
        ($p.branches) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat | $extracted_branch | safe_test($pat; "i"))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (branches)\nBranch pattern is in the denied list"), policy: "branches"}
        elif ($cat.allowed // [] | any(. as $pat | $extracted_branch | safe_test($pat; "i"))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (branches)\nBranch pattern is not in the allowed list"), policy: "branches"}
        else {ok: true} end
      else . end
    else . end |

    # registries: Bash only, package install commands, regex match on command string
    if .ok then
      if ($p | has("registries")) and (if ($p.registries | has("enabled")) then $p.registries.enabled else true end) and ($lower_tool == "bash") and ($cmd_str | test("(npm|pip|cargo|gem|yarn|pnpm)\\s+install"; "i")) then
        ($p.registries) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat | $cmd_str | safe_test($pat; "i"))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (registries)\nRegistry pattern is in the denied list"), policy: "registries"}
        elif ($cat.allowed // [] | any(. as $pat | $cmd_str | safe_test($pat; "i"))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (registries)\nRegistry pattern is not in the allowed list"), policy: "registries"}
        else {ok: true} end
      else . end
    else . end |

    # packages: Bash only, package install commands, regex match on package names
    if .ok then
      if ($p | has("packages")) and (if ($p.packages | has("enabled")) then $p.packages.enabled else true end) and ($lower_tool == "bash") and ($cmd_str | test("(npm|pip|cargo|gem|yarn|pnpm)\\s+install"; "i")) then
        ($p.packages) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat | $cmd_str | safe_test($pat; "i"))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (packages)\nPackage pattern is in the denied list"), policy: "packages"}
        elif ($cat.allowed // [] | any(. as $pat | $cmd_str | safe_test($pat; "i"))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (packages)\nPackage pattern is not in the allowed list"), policy: "packages"}
        else {ok: true} end
      else . end
    else . end |

    # docker: Bash only, docker commands, regex match on command string
    if .ok then
      if ($p | has("docker")) and (if ($p.docker | has("enabled")) then $p.docker.enabled else true end) and ($lower_tool == "bash") and ($cmd_str | test("docker\\s+(run|exec|pull|build|push|compose)"; "i")) then
        ($p.docker) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat | $cmd_str | safe_test($pat; "i"))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (docker)\nDocker pattern is in the denied list"), policy: "docker"}
        elif ($cat.allowed // [] | any(. as $pat | $cmd_str | safe_test($pat; "i"))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (docker)\nDocker pattern is not in the allowed list"), policy: "docker"}
        else {ok: true} end
      else . end
    else . end |

    # domains: all tools, regex match against extracted domains
    if .ok then
      if ($p | has("domains")) and (if ($p.domains | has("enabled")) then $p.domains.enabled else true end) and ($extracted_domains | length > 0) then
        ($p.domains) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat | ($extracted_domains | any(safe_test($pat; "i"))))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (domains)\nBlocked domain pattern: " + $matched_denied), policy: "domains"}
        elif ($cat.allowed // [] | any(. as $pat | ($extracted_domains | any(safe_test($pat; "i"))))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: "[LaneKeep] DENIED by Policy (domains)\nDomain not in the allowed list", policy: "domains"}
        else {ok: true} end
      else . end
    else . end |

    # ips: all tools, regex match against extracted IPs
    if .ok then
      if ($p | has("ips")) and (if ($p.ips | has("enabled")) then $p.ips.enabled else true end) and ($extracted_ips | length > 0) then
        ($p.ips) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat | ($extracted_ips | any(safe_test($pat; "i"))))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (ips)\nBlocked IP pattern: " + $matched_denied), policy: "ips"}
        elif ($cat.allowed // [] | any(. as $pat | ($extracted_ips | any(safe_test($pat; "i"))))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: "[LaneKeep] DENIED by Policy (ips)\nIP not in the allowed list", policy: "ips"}
        else {ok: true} end
      else . end
    else . end |

    # ports: all tools, regex match against extracted ports
    if .ok then
      if ($p | has("ports")) and (if ($p.ports | has("enabled")) then $p.ports.enabled else true end) and ($extracted_ports | length > 0) then
        ($p.ports) as $cat |
        ($cat.default // "allow") as $def |
        ($extracted_ports | map(":" + .)) as $port_strings |
        ($cat.denied // [] | map(select(. as $pat | ($port_strings | any(safe_test($pat; "i"))))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (ports)\nPort pattern is in the denied list"), policy: "ports"}
        elif ($cat.allowed // [] | any(. as $pat | ($port_strings | any(safe_test($pat; "i"))))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (ports)\nPort pattern is not in the allowed list"), policy: "ports"}
        else {ok: true} end
      else . end
    else . end |

    # protocols: all tools, regex match against extracted protocols
    if .ok then
      if ($p | has("protocols")) and (if ($p.protocols | has("enabled")) then $p.protocols.enabled else true end) and ($extracted_protocols | length > 0) then
        ($p.protocols) as $cat |
        ($cat.default // "allow") as $def |
        ($extracted_protocols | map(. + "://")) as $proto_strings |
        ($cat.denied // [] | map(select(. as $pat | ($proto_strings | any(safe_test($pat; "i"))))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (protocols)\nProtocol pattern is in the denied list"), policy: "protocols"}
        elif ($cat.allowed // [] | any(. as $pat | ($proto_strings | any(safe_test($pat; "i"))))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (protocols)\nProtocol pattern is not in the allowed list"), policy: "protocols"}
        else {ok: true} end
      else . end
    else . end |

    # env_vars: Bash only, regex match on command string
    if .ok then
      if ($p | has("env_vars")) and (if ($p.env_vars | has("enabled")) then $p.env_vars.enabled else true end) and ($lower_tool == "bash") then
        ($p.env_vars) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat | $cmd_str | safe_test($pat; "i"))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (env_vars)\nEnv var pattern is in the denied list"), policy: "env_vars"}
        elif ($cat.allowed // [] | any(. as $pat | $cmd_str | safe_test($pat; "i"))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (env_vars)\nEnv var pattern is not in the allowed list"), policy: "env_vars"}
        else {ok: true} end
      else . end
    else . end |

    # governance_paths: Write/Edit only, regex match on file_path
    if .ok then
      if ($p | has("governance_paths")) and (if ($p.governance_paths | has("enabled")) then $p.governance_paths.enabled else true end) and ($lower_tool | test("^(write|edit)$")) and $file_path != "" then
        ($p.governance_paths) as $cat |
        ($cat.default // "allow") as $def |
        ($cat.denied // [] | map(select(. as $pat | $pat | path_match($file_path))) | first // null) as $matched_denied |
        if $matched_denied != null then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (governance_paths)\nPath \"" + $file_path + "\" is in the denied list"), policy: "governance_paths"}
        elif ($cat.allowed // [] | any(. as $pat | $pat | path_match($file_path))) then
          {ok: true}
        elif $def == "deny" then
          {ok: false, reason: ("[LaneKeep] DENIED by Policy (governance_paths)\nPath \"" + $file_path + "\" is not in the allowed list"), policy: "governance_paths"}
        else {ok: true} end
      else . end
    else . end |

    # shell_configs: Write/Edit/Read/Bash, regex match on file_path or command string
    if .ok then
      if ($p | has("shell_configs")) and (if ($p.shell_configs | has("enabled")) then $p.shell_configs.enabled else true end) and ($lower_tool | test("^(write|edit|read|bash)$")) then
        ($p.shell_configs) as $cat |
        ($cat.default // "allow") as $def |
        if $file_path != "" then
          ($cat.denied // [] | map(select(. as $pat | $pat | path_match($file_path))) | first // null) as $matched_denied |
          if $matched_denied != null then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (shell_configs)\nShell config pattern is in the denied list"), policy: "shell_configs"}
          elif ($cat.allowed // [] | any(. as $pat | $pat | path_match($file_path))) then
            {ok: true}
          elif $def == "deny" then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (shell_configs)\nShell config pattern is not in the allowed list"), policy: "shell_configs"}
          else {ok: true} end
        elif $cmd_str != "" then
          ($cat.denied // [] | map(select(. as $pat | $cmd_str | safe_test($pat; "i"))) | first // null) as $matched_denied |
          if $matched_denied != null then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (shell_configs)\nShell config pattern is in the denied list"), policy: "shell_configs"}
          elif ($cat.allowed // [] | any(. as $pat | $cmd_str | safe_test($pat; "i"))) then
            {ok: true}
          elif $def == "deny" then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (shell_configs)\nShell config pattern is not in the allowed list"), policy: "shell_configs"}
          else {ok: true} end
        else . end
      else . end
    else . end |

    # registry_configs: Write/Edit/Read/Bash, glob match on file_path, regex on command string
    if .ok then
      if ($p | has("registry_configs")) and (if ($p.registry_configs | has("enabled")) then $p.registry_configs.enabled else true end) and ($lower_tool | test("^(write|edit|read|bash)$")) then
        ($p.registry_configs) as $cat |
        ($cat.default // "allow") as $def |
        if $file_path != "" then
          ($cat.denied // [] | map(select(. as $pat | $pat | path_match($file_path))) | first // null) as $matched_denied |
          if $matched_denied != null then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (registry_configs)\nRegistry config pattern is in the denied list"), policy: "registry_configs"}
          elif ($cat.allowed // [] | any(. as $pat | $pat | path_match($file_path))) then
            {ok: true}
          elif $def == "deny" then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (registry_configs)\nRegistry config pattern is not in the allowed list"), policy: "registry_configs"}
          else {ok: true} end
        elif $cmd_str != "" then
          ($cat.denied // [] | map(select(. as $pat | $cmd_str | safe_test($pat; "i"))) | first // null) as $matched_denied |
          if $matched_denied != null then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (registry_configs)\nRegistry config pattern is in the denied list"), policy: "registry_configs"}
          elif ($cat.allowed // [] | any(. as $pat | $cmd_str | safe_test($pat; "i"))) then
            {ok: true}
          elif $def == "deny" then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (registry_configs)\nRegistry config pattern is not in the allowed list"), policy: "registry_configs"}
          else {ok: true} end
        else . end
      else . end
    else . end |

    # mcp_servers: any tool starting with mcp__, extract server name
    if .ok then
      if ($p | has("mcp_servers")) and (if ($p.mcp_servers | has("enabled")) then $p.mcp_servers.enabled else true end) and ($lower_tool | test("^mcp__")) then
        ($lower_tool | split("__") | if length >= 2 then .[1] else "" end) as $server |
        if $server != "" then
          ($p.mcp_servers) as $cat |
          ($cat.default // "allow") as $def |
          ($cat.denied // [] | map(select(. as $pat | $server | safe_test($pat; "i"))) | first // null) as $matched_denied |
          if $matched_denied != null then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (mcp_servers)\nMCP server \"" + $server + "\" is in the denied list"), policy: "mcp_servers"}
          elif ($cat.allowed // [] | any(. as $pat | $server | safe_test($pat; "i"))) then
            {ok: true}
          elif $def == "deny" then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (mcp_servers)\nMCP server \"" + $server + "\" is not in the allowed list"), policy: "mcp_servers"}
          else {ok: true} end
        else . end
      else . end
    else . end |

    # hidden_chars: Write/Edit only, scan tool_input for invisible Unicode codepoints
    if .ok then
      if ($p | has("hidden_chars")) and (if ($p.hidden_chars | has("enabled")) then $p.hidden_chars.enabled else true end) and ($lower_tool | test("^(write|edit)$")) then
        ($p.hidden_chars) as $cat |
        ($cat.default // "deny") as $def |
        # Check allowed patterns first (exceptions like ZWJ for emoji)
        if ($cat.allowed // [] | length) > 0 then
          # Remove allowed chars from input, then check denied on remainder
          (reduce ($cat.allowed // [])[] as $allow_pat ($input; gsub($allow_pat; ""))) as $filtered_input |
          ($cat.denied // [] | map(select(. as $pat | $filtered_input | safe_test($pat))) | first // null) as $matched_denied |
          if $matched_denied != null then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (hidden_chars)\nHidden Unicode character detected matching pattern: " + $matched_denied + "\nThese characters can be used for trojan-source or content-smuggling attacks"), policy: "hidden_chars"}
          elif $def == "deny" then
            {ok: true}
          else {ok: true} end
        else
          ($cat.denied // [] | map(select(. as $pat | $input | safe_test($pat))) | first // null) as $matched_denied |
          if $matched_denied != null then
            {ok: false, reason: ("[LaneKeep] DENIED by Policy (hidden_chars)\nHidden Unicode character detected matching pattern: " + $matched_denied + "\nThese characters can be used for trojan-source or content-smuggling attacks"), policy: "hidden_chars"}
          else {ok: true} end
        end
      else . end
    else . end
  ' "$config" 2>/dev/null)
  local jq_exit=$?
  if [ "$jq_exit" -eq 124 ]; then
    RULES_PASSED=false; RULES_DECISION="deny"
    RULES_REASON="[LaneKeep] DENIED: Policy evaluation timed out (possible ReDoS)"
    return 1
  fi

  if [ -z "$result" ]; then
    return 0
  fi

  local ok
  ok=$(printf '%s' "$result" | jq -r '.ok')
  if [ "$ok" = "false" ]; then
    RULES_PASSED=false
    RULES_DECISION="deny"
    RULES_REASON=$(printf '%s' "$result" | jq -r '.reason')
    return 1
  fi
  return 0
}

rules_eval() {
  local tool_name="$1"
  local tool_input="$2"
  RULES_PASSED=true
  RULES_REASON="No rule matched"
  RULES_DECISION="allow"
  RULES_COMPLIANCE="[]"
  RULES_COMPLIANCE_TAGS="[]"
  RULES_INTENT=""

  local config="$LANEKEEP_CONFIG_FILE"

  # Check policies before rules
  if ! policies_check "$tool_name" "$tool_input"; then
    return 1
  fi

  # Single jq call: find first matching enabled rule (first-match-wins)
  local result
  result=$(timeout 5 jq -c --arg tool "$tool_name" --arg input "$tool_input" --arg env "${LANEKEEP_ENV:-}" --arg tier "${LANEKEEP_LICENSE_TIER:-community}" '
    # VULN-07: safe_test wraps test() in try-catch to prevent regex injection crashes
    def safe_test(pat; flags): try test(pat; flags) catch false;

    ($input | ascii_downcase) as $lower_input |
    ($lower_input | gsub("[\u0027\u0022\\\\]"; "")) as $lower_input_clean |
    ($tool | ascii_downcase) as $lower_tool |
    [.rules // [] | to_entries[] |
      select(.value.enabled != false) |
      # Tier filtering: skip rules whose type exceeds current license tier
      select(
        (.value.type // "free") as $t |
        if $tier == "enterprise" then true
        elif $tier == "pro" then ($t != "enterprise")
        else ($t == "free" or $t == null)
        end
      ) |
      .key as $idx | .value as $r |
      select(
        (($r.match.command // "") as $c |
          if $c == "" then true
          else (($lower_input | contains($c | ascii_downcase)) or
                ($lower_input_clean | contains($c | ascii_downcase)))
          end) and
        (($r.match.target // "") as $t |
          if $t == "" then true
          else (($lower_input | safe_test($t; "i")) or
                ($lower_input_clean | safe_test($t; "i")))
          end) and
        (($r.match.tool // "") as $tl |
          if $tl == "" then true
          else ($lower_tool | safe_test($tl; "i"))
          end) and
        (($r.match.pattern // "") as $p |
          if $p == "" then true
          else (($lower_input | safe_test($p; "i")) or
                ($lower_input_clean | safe_test($p; "i")))
          end) and
        (($r.match.env // "") as $e |
          if $e == "" then true
          elif $env == "" then false
          else ($env | safe_test($e; "i"))
          end)
      ) |
      {index: $idx, decision: ($r.decision // "allow"),
       reason: ($r.reason // "Matched rule"),
       intent: ($r.intent // ""),
       category: ($r.category // ""),
       source: ($r.source // "default"),
       compliance: (($r.compliance // []) | join(", ")),
       compliance_arr: ($r.compliance // []),
       compliance_tags: ($r.compliance_tags // [])}
    ] | first // empty
  ' "$config" 2>/dev/null)
  local jq_exit=$?
  if [ "$jq_exit" -eq 124 ]; then
    RULES_PASSED=false; RULES_DECISION="deny"
    RULES_REASON="[LaneKeep] DENIED: Pattern evaluation timed out (possible ReDoS)"
    return 1
  fi

  # No rule matched — allow
  if [ -z "$result" ]; then
    return 0
  fi

  # Extract all matched rule fields in a single jq call (7→1 subprocess)
  local decision reason intent index category compliance source
  eval "$(printf '%s' "$result" | jq -r '
    "decision=" + (.decision | @sh),
    "reason=" + (.reason | @sh),
    "intent=" + (.intent // "" | @sh),
    "index=" + (.index | tostring | @sh),
    "category=" + (.category | @sh),
    "source=" + (.source // "default" | @sh),
    "compliance=" + (.compliance // "" | @sh),
    "RULES_COMPLIANCE=" + (.compliance_arr // [] | tojson | @sh),
    "RULES_COMPLIANCE_TAGS=" + (.compliance_tags // [] | tojson | @sh)')"
  RULES_INTENT="$intent"

  RULES_DECISION="$decision"

  # Build tag suffix: "category [PCI-DSS 3.5.1, GDPR Art.32]" or "category, custom"
  local tag="$category"
  if [ "$source" = "custom" ]; then
    tag="${category:+${category}, }custom"
  fi
  if [ -n "$compliance" ]; then
    tag="${tag:+${tag} }[${compliance}]"
  fi

  # Append intent (the "why") when present
  local intent_line=""
  if [ -n "$intent" ]; then
    intent_line="\nWhy: ${intent}"
  fi

  case "$decision" in
    allow)
      RULES_PASSED=true
      RULES_REASON="$reason"
      return 0
      ;;
    warn)
      RULES_PASSED=true
      RULES_REASON="[LaneKeep] WARNING (Rule #$((index+1)), ${tag}): ${reason}${intent_line}"
      return 0
      ;;
    deny)
      RULES_PASSED=false
      RULES_REASON="[LaneKeep] DENIED by RuleEngine (Rule #$((index+1)), ${tag})\n${reason}${intent_line}"
      return 1
      ;;
    ask)
      RULES_PASSED=false
      RULES_REASON="[LaneKeep] NEEDS APPROVAL (Rule #$((index+1)), ${tag})\n${reason}${intent_line}"
      return 1
      ;;
  esac

  return 0
}
