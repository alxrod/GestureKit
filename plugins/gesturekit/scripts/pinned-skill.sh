#!/bin/bash
# pinned-skill.sh: prints the verify-gestures skill of the GestureKit an app
# pins, for the GestureKit plugin's stub skill, which Claude Code replaces with
# what this prints, so the skill an agent reads always matches the
# gesturekit-drive the app's pinned GestureKit builds.
#
#   pinned-skill.sh [--project DIR] [--extract-into DIR]
#
# 1. The pin: the nearest Package.resolved, the app's own SwiftPM one or an
#    Xcode project's or workspace's (…/xcshareddata/swiftpm/Package.resolved),
#    from the working directory up to the git root, or, with none there,
#    below the working directory; GestureKit's entry is the one whose
#    identity is gesturekit or whose location ends in GestureKit(.git). With
#    no pin, a SwiftPM build's record of GestureKit as a local package
#    (.build/workspace-state.json) names its folder instead. The working
#    directory is --project's when it lies outside it.
# 2. An installed copy: .agents/skills/verify-gestures, the nearest from the
#    working directory up to the git root, as gesturekit-drive install-skill
#    puts it, preferred when its stamp names the pinned commit, and said when
#    it doesn't.
# 3. Otherwise a checkout at the pinned commit: SwiftPM's
#    .build/checkouts/GestureKit; Xcode's
#    DerivedData/<app>/SourcePackages/checkouts/GestureKit, for a DerivedData
#    whose info.plist's WorkspacePath lies in the app; a throwaway
#    DerivedData from a resolve this script suggests, or from a
#    gesture-verify.sh run; or SwiftPM's shared repository cache, from which
#    git archive extracts the skill alone into --extract-into/<commit>.
# 4. It prints where the skill is, then its SKILL.md without frontmatter.
#
# It never reads the skill at another commit than the pin's: with no checkout
# at it, it says what to run. It writes nothing but that extraction, and
# always exits 0, so the stub skill loads and says what it found.
#
# GestureKit's SkillStamp writes the stamp this reads, and the skill's own
# gesture-verify.sh reads it too: keep the three in step (AGENTS.md says
# how). GESTUREKIT_DERIVED_DATA and GESTUREKIT_SWIFTPM_REPOSITORIES change
# where Xcode's DerivedData and SwiftPM's repository cache are looked for.
set -uo pipefail

skill_folder=.agents/skills/verify-gestures
derived_data="${GESTUREKIT_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"
swiftpm_repositories="${GESTUREKIT_SWIFTPM_REPOSITORIES:-$HOME/Library/Caches/org.swift.swiftpm/repositories}"
temporary="${TMPDIR:-/tmp}"
temporary="${temporary%/}"
resolve_folder="$temporary/gesturekit-resolve"
JQ="$(command -v jq || echo /usr/bin/jq)"

say() { printf '%s\n' "$*"; }

# A folder's path with its links resolved, or nothing if it isn't one.
physical() { (cd "$1" 2>/dev/null && pwd -P); }

# The stamp gesturekit-drive install-skill wrote in a SKILL.md ($1): its
# frontmatter's metadata, gesturekit-revision. As gesture-verify.sh reads it.
skill_stamp() {
  awk '
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; inside = 1; next }
    inside && /^---[ \t\r]*$/ { exit }
    inside && /^metadata:[ \t\r]*$/ { meta = 1; next }
    inside && meta && /^[^ \t]/ { meta = 0 }
    inside && meta && /^[ \t]+gesturekit-revision:/ {
      value = $0
      sub(/^[ \t]+gesturekit-revision:[ \t]*/, "", value)
      if (value ~ /^["\047]/) { quote = substr(value, 1, 1); value = substr(value, 2); sub(quote ".*$", "", value) }
      else { sub(/[ \t]+#.*$/, "", value); sub(/[ \t\r]+$/, "", value) }
      print value
      exit
    }
  ' "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

# GestureKit's pin in a Package.resolved ($1), as "revision<TAB>version<TAB>
# branch<TAB>location"; "none" for a file that pins no GestureKit;
# "unreadable" for one jq can't read.
read_pin() {
  "$JQ" -r '
    ((.pins // .object.pins // []) | map(select(
        (((.identity // .package // "") | ascii_downcase) == "gesturekit")
        or ((.location // .repositoryURL // "") | ascii_downcase | sub("/+$"; "") | test("(^|[/:])gesturekit(\\.git)?$"))
    ))) as $pins
    | if ($pins | length) == 0 then "none"
      else $pins[0] | [(.state.revision // ""), (.state.version // ""), (.state.branch // ""), (.location // .repositoryURL // "")] | @tsv
      end
  ' "$1" 2>/dev/null || echo unreadable
}

# The Package.resolved files directly in a folder ($1): SwiftPM's, and each
# Xcode workspace's and project's.
pin_files_in() {
  local file
  for file in "$1/Package.resolved" \
    "$1"/*.xcworkspace/xcshareddata/swiftpm/Package.resolved \
    "$1"/*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved; do
    [ -f "$file" ] && say "$file"
  done
  return 0
}

# Whether a folder ($1) is a git checkout of its own at a commit ($2).
checkout_at() {
  [ -e "$1/.git" ] && [ "$(git -C "$1" rev-parse HEAD 2>/dev/null)" = "$2" ]
}

# How a pin's ref reads: "branch main", "version 1.2.0", or nothing.
pin_ref() {
  if [ -n "$2" ]; then say "version $2"; elif [ -n "$3" ]; then say "branch $3"; fi
}

# A path as the app's folder names it, relative to the git root where it's
# inside it.
shown() {
  case "$1" in
    "$root") say "." ;;
    "$root"/*) say "${1#"$root"/}" ;;
    *) say "$1" ;;
  esac
}

# Prints the skill in a folder ($1), headed by the lines given after it.
print_skill() {
  local folder="$1" line
  shift
  say "# verify-gestures, matched to the GestureKit this project pins"
  say ""
  for line in "$@"; do say "$line"; done
  say ""
  say "This skill's folder is \`$folder\`. Wherever the skill below says \`.agents/skills/verify-gestures\`, it means that folder, so \`\$V\` is \`$folder/scripts/gesture-verify.sh\`. Run it from the project's root, \`$root\`."
  say ""
  awk 'NR == 1 && /^---[ \t\r]*$/ { frontmatter = 1; next } frontmatter && /^---[ \t\r]*$/ { frontmatter = 0; next } !frontmatter' "$folder/SKILL.md"
}

# What to run to check out the pinned commit, for each pin file given.
how_to_resolve() {
  local file folder
  for file in "$@"; do
    case "$file" in
      */xcshareddata/swiftpm/Package.resolved)
        folder="${file%/xcshareddata/swiftpm/Package.resolved}"
        case "$folder" in
          *.xcodeproj/project.xcworkspace)
            say "- For \`$(shown "${folder%/project.xcworkspace}")\`, resolve into a throwaway DerivedData, never Xcode's own: \`xcodebuild -resolvePackageDependencies -project $(shown "${folder%/project.xcworkspace}") -scheme <scheme> -derivedDataPath \"$resolve_folder\"\`." ;;
          *)
            say "- For \`$(shown "$folder")\`, resolve into a throwaway DerivedData, never Xcode's own: \`xcodebuild -resolvePackageDependencies -workspace $(shown "$folder") -scheme <scheme> -derivedDataPath \"$resolve_folder\"\`." ;;
        esac ;;
      *)
        say "- For the package at \`$(shown "$(dirname "$file")")\`: \`swift package resolve --package-path $(shown "$(dirname "$file")")\`, which checks out its pins in its .build." ;;
    esac
  done
}

main() {
  local project="" extract_into=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project="${2:-}"; shift 2 || shift ;;
      --extract-into) extract_into="${2:-}"; shift 2 || shift ;;
      *) shift ;;
    esac
  done

  if [ ! -x "$JQ" ]; then
    say "# verify-gestures: jq is missing"
    say ""
    say "This skill reads Package.resolved with jq, which macOS ships at /usr/bin/jq from macOS 15. Install jq, or read \`.agents/skills/verify-gestures/SKILL.md\` in the GestureKit checkout at the commit your Package.resolved pins."
    return 0
  fi

  # Where to look: from the working directory up to the git root.
  local start project_root
  start="$(pwd -P)"
  if [ -n "$project" ] && project_root="$(physical "$project")"; then
    case "$start/" in "$project_root/"*) ;; *) start="$project_root" ;; esac
  fi
  local directories=() directory="$start"
  root=""
  while :; do
    directories+=("$directory")
    if [ -e "$directory/.git" ]; then root="$directory"; break; fi
    [ "$directory" = / ] && break
    directory="$(dirname "$directory")"
  done
  if [ -z "$root" ]; then directories=("$start"); root="$start"; fi

  # The installed copy, and its stamp.
  local installed="" stamp=""
  for directory in "${directories[@]}"; do
    if [ -f "$directory/$skill_folder/SKILL.md" ]; then installed="$directory/$skill_folder"; break; fi
  done
  [ -n "$installed" ] && stamp="$(skill_stamp "$installed/SKILL.md")"

  # The pin: the nearest folder's, else below the working directory.
  local pins=() notes=() file line
  for directory in "${directories[@]}"; do
    while IFS= read -r file; do
      line="$(read_pin "$file")"
      case "$line" in
        none) notes+=("$(shown "$file") pins no GestureKit.") ;;
        unreadable) notes+=("$(shown "$file") couldn't be read as JSON.") ;;
        *) pins+=("$file"$'\t'"$line") ;;
      esac
    done < <(pin_files_in "$directory")
    [ ${#pins[@]} -gt 0 ] && break
  done
  if [ ${#pins[@]} -eq 0 ]; then
    while IFS= read -r file; do
      line="$(read_pin "$file")"
      case "$line" in none|unreadable) ;; *) pins+=("$file"$'\t'"$line") ;; esac
    done < <(find "$start" -maxdepth 7 \( -name .build -o -name DerivedData -o -name .git -o -name node_modules \
      -o -name Pods -o -name checkouts -o -name artifacts -o -name build \) -prune -o -name Package.resolved -type f -print 2>/dev/null | sort)
  fi

  if [ ${#pins[@]} -eq 0 ]; then
    # A local package, as SwiftPM recorded it, or GestureKit's own checkout.
    local state local_folder=""
    for directory in "${directories[@]}"; do
      state="$directory/.build/workspace-state.json"
      [ -f "$state" ] || continue
      local_folder="$("$JQ" -r '[(.object.dependencies // [])[] | .packageRef
          | select(((.identity // "") | ascii_downcase) == "gesturekit" and (.kind == "fileSystem" or .kind == "localSourceControl"))
          | .location][0] // empty' "$state" 2>/dev/null)"
      [ -n "$local_folder" ] && break
    done
    if [ -n "$local_folder" ]; then
      if [ -f "$local_folder/$skill_folder/SKILL.md" ]; then
        print_skill "$local_folder/$skill_folder" \
          "GestureKit is a local package here, \`$local_folder\`, as \`$(shown "$state")\` records it: SwiftPM builds that folder as it is, with no pin, so its skill is the one that matches."
      else
        say "# verify-gestures: the local GestureKit has no skill"
        say ""
        say "GestureKit is a local package here, \`$local_folder\`, as \`$(shown "$state")\` records it, and that folder has no \`$skill_folder\`: it predates the skill. Update that checkout to a GestureKit commit that has it."
      fi
      return 0
    fi
    if [ -f "$root/$skill_folder/SKILL.md" ] && grep -q 'name: "GestureKit"' "$root/Package.swift" 2>/dev/null; then
      print_skill "$root/$skill_folder" "This is GestureKit's own repository, so its own skill is the one that matches."
      return 0
    fi
    say "# verify-gestures: no GestureKit pin found"
    say ""
    say "No Package.resolved from \`$start\` up to \`$root\`, or below it, pins GestureKit, and no SwiftPM build here records it as a local package, so there's no telling which GestureKit's skill matches this project, and none is guessed."
    say ""
    say "- If the project depends on GestureKit, resolve its packages so Package.resolved pins it: \`swift package resolve\` in the package's folder, or for an Xcode project \`xcodebuild -resolvePackageDependencies -project <App>.xcodeproj -scheme <scheme> -derivedDataPath \"$resolve_folder\"\`. Then load this skill again."
    say "- If it depends on GestureKit by a path in Xcode, read \`$skill_folder/SKILL.md\` in that folder."
    for line in "${notes[@]+"${notes[@]}"}"; do say "- $line"; done
    return 0
  fi

  # One commit, or say they differ.
  local revisions revision version branch location
  revisions="$(for line in "${pins[@]}"; do cut -f2 <<<"$line"; done | sort -u)"
  if [ "$(wc -l <<<"$revisions" | tr -d ' ')" -gt 1 ]; then
    say "# verify-gestures: the project pins GestureKit at more than one commit"
    say ""
    for line in "${pins[@]}"; do say "- \`$(shown "$(cut -f1 <<<"$line")")\` pins GestureKit $(cut -f2 <<<"$line")."; done
    say ""
    say "Resolve them to one commit, or work from the folder whose pin you build, then load this skill again."
    return 0
  fi
  # cut, not read: read folds a run of tabs, so an empty field would vanish.
  revision="$(cut -f2 <<<"${pins[0]}")"
  version="$(cut -f3 <<<"${pins[0]}")"
  branch="$(cut -f4 <<<"${pins[0]}")"
  location="$(cut -f5 <<<"${pins[0]}")"
  local pin_files=() ref
  for line in "${pins[@]}"; do pin_files+=("$(cut -f1 <<<"$line")"); done
  ref="$(pin_ref "$revision" "$version" "$branch")"
  local pinned_by
  pinned_by="$(for file in "${pin_files[@]}"; do printf '`%s`, ' "$(shown "$file")"; done)"
  pinned_by="${pinned_by%, }"
  if [[ ! "$revision" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
    say "# verify-gestures: GestureKit's pin names no commit"
    say ""
    say "$pinned_by pins GestureKit from \`$location\` with no full commit (\"$revision\"). Resolve the packages again, then load this skill again."
    return 0
  fi
  local described="GestureKit $revision${ref:+ ($ref)}"

  # The installed copy, if it came from the pinned commit; else say so.
  local installed_note=""
  if [ -n "$installed" ]; then
    if [ "$stamp" = "$revision" ]; then
      print_skill "$installed" \
        "It's the copy \`gesturekit-drive install-skill\` put in \`$(shown "$installed")\`, stamped with $described, which $pinned_by pins."
      return 0
    elif [ -n "$stamp" ]; then
      installed_note="The copy installed in \`$(shown "$installed")\` came from GestureKit $stamp, not the pinned commit, so it isn't the one read here. Bring it in step with the pinned GestureKit's driver: \`gesturekit-drive install-skill --update\` (\`swift run gesturekit-drive install-skill --update\` in a package)."
    else
      installed_note="The copy installed in \`$(shown "$installed")\` carries no stamp naming the commit it came from, so it isn't the one read here. Replace it with the pinned GestureKit's: \`gesturekit-drive install-skill --update\` (\`swift run gesturekit-drive install-skill --update\` in a package)."
    fi
  fi

  # Checkouts at the pinned commit.
  local folders=() looked=() predates="" dirty=""
  for file in "${pin_files[@]}"; do
    case "$file" in */xcshareddata/swiftpm/Package.resolved) ;; *) folders+=("$(dirname "$file")/.build/checkouts") ;; esac
  done
  for directory in "${directories[@]}"; do folders+=("$directory/.build/checkouts"); done
  local info workspace workspace_folder
  for info in "$derived_data"/*/info.plist; do
    [ -f "$info" ] || continue
    workspace="$(plutil -extract WorkspacePath raw -o - "$info" 2>/dev/null)" || continue
    workspace_folder="$(physical "$(dirname "$workspace")")" || continue
    case "$workspace_folder/" in "$root/"*) folders+=("$(dirname "$info")/SourcePackages/checkouts") ;; esac
  done
  folders+=("$resolve_folder/SourcePackages/checkouts")
  for file in "$temporary"/gesture-verify/*/DerivedData/SourcePackages/checkouts; do folders+=("$file"); done

  local folder checkout name found=""
  for folder in "${folders[@]}"; do
    [ -d "$folder" ] || continue
    for checkout in "$folder"/*; do
      name="$(basename "$checkout" | tr '[:upper:]' '[:lower:]')"
      [ "$name" = gesturekit ] || continue
      looked+=("$checkout")
      checkout_at "$checkout" "$revision" || continue
      if [ ! -f "$checkout/$skill_folder/SKILL.md" ]; then predates="$checkout"; continue; fi
      if [ -n "$(git -C "$checkout" status --porcelain -- "$skill_folder" 2>/dev/null)" ]; then dirty="$checkout"; continue; fi
      found="$checkout/$skill_folder"
      break 2
    done
  done

  # Else SwiftPM's shared cache, the skill alone extracted from it.
  local repository git_dir extracted="" extract_root
  if [ -z "$found" ] && [ -z "$predates" ]; then
    for repository in "$swiftpm_repositories"/*; do
      name="$(basename "$repository" | tr '[:upper:]' '[:lower:]')"
      case "$name" in gesturekit-*) ;; *) continue ;; esac
      git_dir="$repository"
      [ -d "$repository/.git" ] && git_dir="$repository/.git"
      looked+=("$repository")
      git --git-dir "$git_dir" cat-file -e "$revision^{commit}" 2>/dev/null || continue
      if ! git --git-dir "$git_dir" cat-file -e "$revision:$skill_folder/SKILL.md" 2>/dev/null; then
        predates="$repository"
        continue
      fi
      extract_root="$extract_into"
      if [[ "$extract_root" != /* ]] || ! mkdir -p "$extract_root" 2>/dev/null || [ ! -w "$extract_root" ]; then
        extract_root="$HOME/Library/Caches/gesturekit-pinned-skills"
        mkdir -p "$extract_root" 2>/dev/null || continue
      fi
      if [ ! -f "$extract_root/$revision/$skill_folder/SKILL.md" ]; then
        local staging
        staging="$(mktemp -d "$extract_root/.extracting.XXXXXX" 2>/dev/null)" || continue
        if git --git-dir "$git_dir" archive --format=tar "$revision" "$skill_folder" | tar -x -C "$staging" 2>/dev/null \
          && [ -f "$staging/$skill_folder/SKILL.md" ]; then
          rm -rf "${extract_root:?}/$revision"
          mv "$staging" "$extract_root/$revision" || { rm -rf "$staging"; continue; }
        else
          rm -rf "$staging"
          continue
        fi
      fi
      found="$extract_root/$revision/$skill_folder"
      extracted="$repository"
      break
    done
  fi

  if [ -n "$found" ]; then
    local whence="the checkout \`$(dirname "$(dirname "$(dirname "$found")")")\`"
    [ -n "$extracted" ] && whence="SwiftPM's repository cache, \`$extracted\`, extracted with git archive"
    print_skill "$found" \
      "It's the skill of $described, which $pinned_by pins, read from $whence." \
      ${installed_note:+"$installed_note"}
    return 0
  fi

  if [ -n "$predates" ]; then
    say "# verify-gestures: the pinned GestureKit predates the skill"
    say ""
    say "$pinned_by pins $described, and that commit, in \`$predates\`, has no \`$skill_folder\`: the skill came later. Update GestureKit to a commit that has it (\`swift package update GestureKit\`, or Xcode's File > Packages > Update to Latest Package Versions), then load this skill again. A newer skill wouldn't match the gesturekit-drive this commit builds."
    [ -n "$installed_note" ] && { say ""; say "$installed_note"; }
    return 0
  fi

  say "# verify-gestures: $described isn't checked out here"
  say ""
  say "$pinned_by pins $described, and no checkout of that commit was found, so the skill that matches it can't be read, and none at another commit is guessed."
  [ -n "$dirty" ] && say "The checkout at \`$dirty\` is at that commit, but its skill has changes not committed there."
  if [ ${#looked[@]} -gt 0 ]; then
    say ""
    say "GestureKit checkouts at other commits: $(for checkout in "${looked[@]}"; do printf '`%s`, ' "$checkout"; done | sed 's/, $//')."
  fi
  say ""
  say "Check the pinned commit out, then load this skill again:"
  how_to_resolve "${pin_files[@]}"
  [ -n "$installed_note" ] && { say ""; say "$installed_note"; }
  return 0
}

main "$@" || true
exit 0
