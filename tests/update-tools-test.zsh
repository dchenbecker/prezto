#!/usr/bin/env zsh
# Tests for how bin/update-tools.sh reports asdf and Node.js updates, run
# against a stub asdf so nothing on the real system changes.

setopt NO_UNSET

script=${0:A:h:h}/bin/update-tools.sh
stub_dir=$(mktemp -d) || exit 1
trap 'rm -rf -- "$stub_dir"' EXIT
# The script reads the user-wide version from here.
export HOME=$stub_dir/home
mkdir -p $HOME

cat > $stub_dir/asdf <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_CALLS"
case "$1" in
  latest) echo 2.0 ;;
  # Answers like a project override anywhere but the user-wide context.
  current)
    version=$STUB_CURRENT
    [ "$PWD" = "$HOME" ] || version=9.9
    echo "$2 ${ASDF_FOO_VERSION:-${ASDF_NODEJS_VERSION:-$version}}" ;;
  # STUB_INSTALLED=0 means version 2.0 is absent until `install` is called.
  # As real asdf does, the selected version is starred.
  list)
    for v in 1.0 2.0; do
      [ "$v" = 2.0 ] && [ "$STUB_INSTALLED" != 1 ] && continue
      if [ "$v" = "$STUB_CURRENT" ]; then echo " *$v"; else echo "  $v"; fi
    done ;;
  where)
    [ "$STUB_INSTALLED" = 1 ] || [ "$3" != 2.0 ] \
      || grep -q "^install $2 " "$STUB_CALLS" || exit 1
    echo "$STUB_DIR/$2/$3" ;;
esac
STUB
chmod +x $stub_dir/asdf

# Each fake Node.js lists the packages in its `packages` file as
# "name<TAB>version", which the fake node passes through in place of parsing.
for version in 1.0 2.0; do
  mkdir -p $stub_dir/nodejs/$version/bin
  print '#!/bin/sh\nexec cat' > $stub_dir/nodejs/$version/bin/node
  cat > $stub_dir/nodejs/$version/bin/npm <<'STUB'
#!/bin/sh
case "$1" in
  ls) cat "${0%/bin/npm}/packages" ;;
  install) echo "npm $*" >> "$STUB_CALLS" ;;
esac
STUB
  chmod +x $stub_dir/nodejs/$version/bin/{node,npm}
done

failed=0

# check NAME CURRENT INSTALLED EXPECTED_SUMMARY EXPECT_INSTALL_AND_SET(0|1)
check() {
  local name=$1 current=$2 installed=$3 expected=$4 expect_set=$5
  local out did_set=0 did_install=0
  : >| $stub_dir/calls
  out=$(STUB_DIR=$stub_dir STUB_CALLS=$stub_dir/calls STUB_CURRENT=$current STUB_INSTALLED=$installed \
    PATH=$stub_dir:$PATH UPDATE_TOOLS_TMPDIR= zsh -f $script --asdf foo 2>&1)
  grep -q '^set -u foo 2.0$' $stub_dir/calls && did_set=1
  grep -q '^install foo 2.0$' $stub_dir/calls && did_install=1
  if [[ "$out" == *"$expected"* && $did_set == $expect_set && $did_install == $expect_set ]]; then
    print "ok   $name"
  else
    print "FAIL $name (install: $did_install, set -u: $did_set)\n$out"
    failed=1
  fi
}

check "current version is left alone" 2.0 1 "asdf foo: already 2.0" 0
check "older version is updated" 1.0 1 "asdf foo: user-wide default set to 2.0" 1
check "missing install is repaired" 2.0 0 "asdf foo: user-wide default set to 2.0" 1
ASDF_FOO_VERSION=2.0 \
  check "environment override is ignored" 1.0 1 "asdf foo: user-wide default set to 2.0" 1

# check_node NAME CURRENT INSTALLED EXPECTED_CALLS [TARGET_PACKAGES] [FLAGS]
# EXPECTED_CALLS lists the state-changing calls, one per line.
check_node() {
  local name=$1 current=$2 installed=$3 expected=$4 target_packages=${5-} flags=${6-}
  local out calls summary="asdf nodejs: already 2.0"
  : >| $stub_dir/calls
  print 'pkg\t1.0' >| $stub_dir/nodejs/1.0/packages
  print -rn -- "$target_packages" >| $stub_dir/nodejs/2.0/packages
  [[ "$expected" == *"set -u"* ]] && summary="asdf nodejs: $current -> 2.0"
  [[ "$expected" == *"set -u"* && $current == 2.0 ]] && summary="asdf nodejs: reinstalled 2.0"
  [[ "$flags" == --dry-run ]] && summary="copy 1 global npm package(s)"
  out=$(STUB_DIR=$stub_dir STUB_CALLS=$stub_dir/calls \
    STUB_CURRENT=$current STUB_INSTALLED=$installed \
    PATH=$stub_dir:$PATH UPDATE_TOOLS_TMPDIR= zsh -f $script --node 2.0 ${=flags} 2>&1)
  calls=$(grep -E '^(install|set|npm) ' $stub_dir/calls)
  if [[ "$out" == *"$summary"* && "$calls" == "$expected" ]]; then
    print "ok   $name"
  else
    print "FAIL $name\ncalls:\n$calls\n$out"
    failed=1
  fi
}

switch=$'install nodejs 2.0\nset -u nodejs 2.0'
copy='npm install --global pkg@1.0'
have=$'pkg\t1.0'

check_node "current node is left alone" 2.0 1 "" $have
check_node "current node gains a missing package" 2.0 1 $copy
check_node "older node is switched and packages copied" 1.0 0 $switch$'\n'$copy
check_node "installed node is selected without recopying" 1.0 1 $switch $have
check_node "missing node install is repaired" 2.0 0 $switch$'\n'$copy
check_node "differing package version is replaced" 1.0 1 $switch$'\n'$copy $'pkg\t0.9'
check_node "current node's packages count as present" 2.0 1 "" $'pkg\t2.0'
check_node "dry run changes nothing" 1.0 1 "" "" --dry-run

exit $failed
