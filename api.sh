#!/bin/bash

# Purpose: Bash binding for #btsync API
# Author : It's me, Anh K. Huynh
# Date   : Today, 2018 Aug 21st
# License: MIT
# Source : https://github.com/icy/cnystb

export BTSYNC_TOKEN="${BTSYNC_TOKEN:-}"
export BTSYNC_COOKIE="${BTSYNC_COOKIE:-}"
export BTSYNC_HOST="${BTSYNC_HOST:-localhost:8888}"
export BTSYNC_VERSION=

export __now="$(date +%s)"
export __user="${BTSYNC_USER:-admin}"
export __pass="${BTSYNC_PASSWD:-foobar}"
export __agent="btsync/cnystb bash binding"

unset  __BTSYNC_ECHO
unset  __BTSYNC_PARAMS
unset  __BTSYNC_PERL_OK

## system utils

__debug() {
  if [[ "$BTSYNC_DEBUG" == "debug" ]]; then
    echo >&2 "(debug) $@"
  fi
}

__debug_cat() {
  if [[ "$BTSYNC_DEBUG" == "debug" ]]; then
    while read _line; do
      echo >&2 "(debug) $@: $_line"
    done
  else
    cat >/dev/null
  fi
}

# The most used `curl` method
__curl() {
  __debug "$FUNCNAME: $@"
  local _action="$1"; shift

  ${BTSYNC_CURL:-curl} -Ls \
    "http://$BTSYNC_HOST/gui/?token=$BTSYNC_TOKEN&action=$_action&t=$__now" \
    -u "$__user:$__pass" \
    -X POST \
    -H "Host: $BTSYNC_HOST" \
    -H "Referer: http://$BTSYNC_HOST/gui/" \
    -H "User-Agent: $__agent" \
    -H "Cookie: GUID=${BTSYNC_COOKIE}" \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H 'Accept-Language: en-US,en;q=0.5' \
    -H 'Accept: application/json, text/javascript, */*; q=0.01' \
    "$@"

  echo
}

# A simple GET query
__curl_get() {
  __debug "$FUNCNAME: $@"
  local _section="$1"; shift

  ${BTSYNC_CURL:-curl} -Ls \
    "http://$BTSYNC_HOST/$_section" \
    -u "$__user:$__pass" \
    -X GET \
    -H "Host: $BTSYNC_HOST" \
    -H "Referer: http://$BTSYNC_HOST/gui/" \
    -H "User-Agent: $__agent" \
    "$@"
}

# Check if `perl/JSON` is working. If `not`, __exit
__perl_check() {
  [[ -z "$__BTSYNC_PERL_OK" ]] || return 0

  perl -e 'use JSON' >/dev/null 2>&1 \
  || __exit "perl/JSON not found"

  perl -e 'use URI::Escape' >/dev/null 2>&1 \
  || __exit "perl/URI::Escape not found"

  export __BTSYNC_PERL_OK=1
}

# Read user input from $__BTSYNC_PARAMS. This variable is a list
# of user's input, separated by a `###` group. Example
#   foobar###dir=/path/to/###
#
# To get the `dir` variable, this method is invoked like this
#   __input_fetch dir
#
__input_fetch() {
  local _section="$1"
  local _found=""

  while read _u; do
    [[ -n "$_u" ]] || continue
    echo "$_u" \
    | grep -qis "^$_section="
    if [[ $? -eq 0 ]]; then
      _found="$(echo "$_u" | sed -e "s/^$_section=//" | head -1)"
      break
    fi
  done \
    < <(echo "$__BTSYNC_PARAMS" | sed -e 's/###/\n/g' )

  echo "$_found"
}

# Encode the URL before using it in `curl`.
# See https://gist.github.com/moyashi/4063894
# NOTE: This awk version only works with ASCII characters.
__url_encode() {
  perl -e '
    use URI::Escape;
    while (<>) {
      printf("%s", uri_escape($_));
    }
    '
}

## internal methods

# Return the token a valid token for the session
__token_get() {
  __curl_get "gui/token.html?t=$__now" \
    -X POST \
    -H "Cookie: GUID=${BTSYNC_COOKIE}" \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H 'Accept: */*' \
  | sed -e 's/[<>]/\n/g' \
  | grep -iE '[a-z0-9_-]{10,}'
}

# Return the cookie for the session
__cookie_get() {
  __curl_get "gui/" -o /dev/null -c - \
  | grep GUID \
  | awk '{print $NF}'
  [[ "${PIPESTATUS[1]}" == "0" ]]
}

# Print error message in JSON format, and exit(1)
__exit() {
  echo "{\"error\": 900, \"message\": \"${@:-missing argument}\", \"at\": $__now}"
  exit 1
}

# Fetch `dir` variable from user' input. This calls `__input_fetch` method
# and does some check to make sure `dir` is valid.
__input_fetch_dir() {
  local _dir

  _dir="$(__input_fetch dir)"
  if [[ -z "$_dir" ]]; then
    __exit "Missing argument. Please specify dir=<something>"
  fi

  if [[ "${_dir:0:1}" != "/" ]]; then
    __exit "Directory name be started by a slash. Otherwise, new directory may be created in a random place."
  fi

  echo -n $_dir | __url_encode
}

# Fetch `key` from user' input, or generate new key pair
# by invoking `key_get` method.
__input_fetch_key() {
  local _key="$(__input_fetch key)"

  if [[ -z "$_key" ]]; then
    _key="$( \
    export __BTSYNC_PARAMS="$__BTSYNC_PARAMS###master=1"
    key_get \
    | perl -e '
        use JSON;
        my $pair = decode_json(<>);
        my $rwkey = $pair->{"read_write"};
        print $rwkey . "\n";
      '
    )"
  fi

  echo -n $_key | __url_encode
}

# Return 0, 1 (valid), or default value (from $1, or 0)
__zero_or_one() {
  local _zero=0
  local _one=1

  case "$1" in
    ":B") _zero="false"; _one="true" ; shift ;;
    ":N") shift;
  esac

  while read _line; do
    case "$_line" in
    "0") echo $_zero ;;
    "1") echo $_one ;;
    *)
      if [[ "$1" == "0" ]]; then
        echo "$_zero"
      else
        echo "$_one"
      fi
      ;;
    esac
  done
}

__version_detect() {
  local _ret=

  __curl_get 'gui/js/license.js' \
    | grep -q 'licenseagreed'

  _ret=( "${PIPESTATUS[@]}" )

  if [[ "${_ret[0]}${_ret[1]}" == "00" ]]; then
    export BTSYNC_VERSION="1.4"
    export __BTSYNC_DIR_ATTR="path"
  elif [[ "${_ret[0]}" == "0" ]]; then
    export BTSYNC_VERSION="1.3"
    export __BTSYNC_DIR_ATTR="name"
  else
    export BTSYNC_VERSION=""
  fi

  __debug "$FUNCNAME: BTSYNC_VERSION = $BTSYNC_VERSION"

  if [[ -z "$BTSYNC_VERSION" ]]; then
    __exit "Unable to detect btsync version. Is btsync running?"
  fi
}

__version_selector() {
  case $BTSYNC_VERSION in
    "1.3") echo "$1" ;;
    "1.4") echo "$2" ;;
  esac
}

## exporting

# Valide if input method is valid
__validate_method() {
  case "$1" in
  'token/get') ;;
  'curl/header/get') ;;
  'cookie/get') ;;
  'folder/get') ;;
  'setting/get') ;;
  'folder/setting/get') ;;
  'os/type/get') ;;
  'version/get') ;;
  'speed/get') ;;
  'key/get') ;;
  'os/dir/create') ;;
  'folder/create') ;;
  'folder/host/get') ;;
  'key/onetime/get') ;;
  'folder/setting/update') ;;
  'folder/host/create') ;;
  'folder/host/delete') ;;
  'folder/delete') ;;
  'license/update') ;;
  'raw/get') ;;
  *) echo "$1"; return 1 ;;
  esac
  echo "$1" | sed -e 's#/#_#g'
}

# This is as same as __folder_get, but for a single directory.
# Example usage
#   $0 directory_name
#   $0 -k key_string
# Note:
#   Multiple shared folders can share the same one-time secret key.
#   However, only one of them is active; other key will be put the
#   shared folder in 'pending status' (Pending receipt of master secret).
#   If this is the case, the first restul will be returned.
#   Looking up by key is not good.
__folder_get_single() {
  __debug "$FUNCNAME: fetch folder => $@"

  __curl "getsyncfolders&discovery=0" \
  | perl -e '
    use JSON;

    my $dir = shift(@ARGV);
    my $key;
    my $option = 0;
    if ($dir eq "-k") {
      $key = shift(@ARGV);
      $option = 1;
    }
    my $jS0n = do { local $/; <STDIN> };
    my $json = decode_json( $jS0n );
    my $folders = $json->{"folders"};

    if ($option eq 0) {
      $dir =~ s#/+$##;
      $dir =~ s#//+#/#;
      for ( keys @{$folders} ) {
        my $d = $folders->[$_];
        my $dname = $d->{$ENV{"__BTSYNC_DIR_ATTR"}};
        $dname =~ s#/+$##;
        $dname =~ s#//+#/#;
        if ($dname eq $dir) {
          print encode_json($d);
          print "\n";
          exit(0);
        }
      }
    }
    else {
      for ( keys @{$folders} ) {
        my $d = $folders->[$_];
        if ($d->{"secret"} eq $key || $d->{"readonlysecret"} eq $key) {
          print encode_json($d);
          print "\n";
          exit(0);
        }
      }
    }

    print "{\"error\": 900, \"message\": \"The path you specified is not valid.\"}\n";
    exit 1;
  ' \
    -- "$@"
}

# Input : <dir> or <key>
# Output: <primary>|<ro_key (if any)>
# Desc. : This method will get a information from a *single* folder,
#         (by its <key> or <dir>), and prints folder' keys in format
#           <secret_key>|<rosecret>
# Note  : If folder is a RO node, <secret_key> is a RO key,
#         and <rosecret> will be empty
__folder_get_key() {
  folder_get \
  | perl -e '
      use JSON;
      my $json = decode_json(<>);
      my $secret = $json->{"secret"};
      my $rosecret = $json->{"readonlysecret"};
      printf "%s|%s\n", $secret, $rosecret;
    '
}

# Input : <dir> or <key>
# Output: <dir>|<primary key>
# Desc. : This method is used by other methods, to get <dir> and <key>
#         which are required for #btsync api call. Though <dir> is unique,
#         there is a case when two different folder can share a same <key>.
__folder_get_name_and_key() {
  local _dir="$(__input_fetch dir)"
  local _key="$(__input_fetch key)"

  if [[ -n "$_dir" ]]; then
    __folder_get_single "$_dir" \
    | perl -e '
        use JSON;
        my $json = decode_json(<>);
        printf "%s|%s\n", $json->{$ENV{"__BTSYNC_DIR_ATTR"}}, $json->{"secret"};
      '
  elif [[ -n "$_key" ]]; then
    __folder_get_single -k "$_key" \
    | perl -e '
        use JSON;
        my $json = decode_json(<>);
        printf "%s|%s\n", $json->{$ENV{"__BTSYNC_DIR_ATTR"}}, $json->{"secret"};
      '
  else
    echo '|'
  fi
}

# Input : A primary <key> as the first argument ($1)
# Output: The <rokey> of the <rwkey>, the <erokey> (if any)
# Desc. : This method is primarily used by <key/get>. The idea is simple.
#         We will check if the <key> is being used for any folder. If 'yes',
#         that folder's information will be used to provide other keys.
#         If 'not', we will create a *random* directory on the server,
#         which has <key> as primary one. This *random* will be removed
#         after its key information is disclosured.
#
#         To get a *random* key, we call to <generatesecret> method.
# Note  : This method will generate many empty / temporarily folders
#           /tmp/cnystb/*
#         It's important to have a periodly task to remove those directories.
__key_push_and_pull() {
  local _random=
  local _key="$1" # should be a RW or ERW key
  local _nkey
  local _defdir=""

  _nkey="$( \
    export __BTSYNC_PARAMS="key=$_key"
    __folder_get_key
    )"

  if [[ "$_nkey" != "|" ]]; then
    echo "$_nkey"
    return
  fi

  _random="$( \
    __curl "generatesecret" \
    | perl -e '
        use JSON;
        my $json = decode_json(<>);
        printf "%s\n", $json->{"secret"} || $json->{"value"}->{"secret"};
      '
    )"

  __debug "$FUNCNAME: random value => $_random"

  echo "$_random" | grep -Esq '^[A-Z2-7]{33}$'
  if [[ $? -ge 1 ]]; then
    echo "|"
    return
  fi

  if [[ "$BTSYNC_VERSION" == "1.4" ]]; then
    _defdir="$( \
      export __BTSYNC_PARAMS="";
      folder_setting_get \
      | perl -e '
          use JSON;
          my $json = decode_json(<>);
          print $json->{"folders"}->{"default"};
        '
      )"

    __debug "$FUNCNAME: default remote directory => $_defdir"

    # For the latest version of 1.4:
    # ~~~
    # Well, we need to create a temporary directory first.
    # new 1.4 doesn't allow to create nested folder... but wait,
    # if this default folder is under a symlink we can't create
    # new directory...
    #
    ( export __BTSYNC_PARAMS="dir=$_defdir/cnystb";
      os_dir_create | __debug_cat "$FUNCNAME/os/dir/create" )

    _defdir="$_defdir/cnystb/$_random"
  else
    _defdir="/tmp/cnystb/$_random"
  fi

  ( export __BTSYNC_PARAMS="dir=$_defdir###key=$_key";
    folder_create | __debug_cat "$FUNCNAME/folder/create" )

  _nkey="$( \
    export __BTSYNC_PARAMS="dir=$_defdir"
    __folder_get_key
    )"

  echo "$_nkey"

  ( export __BTSYNC_PARAMS="dir=$_defdir";
    folder_delete | __debug_cat "$FUNCNAME/folder/delete" )
}

## puplic method

curl_header_get() {
  echo "{\"cookie\": \"$BTSYNC_COOKIE\", \"token\": \"$BTSYNC_TOKEN\", \"at\": $__now}"
}

cookie_get() {
  BTSYNC_COOKIE="${1:-$BTSYNC_COOKIE}"
  if [[ -z "$BTSYNC_COOKIE" ]]; then
    export BTSYNC_COOKIE="$(__cookie_get)"
    if [[ -z "$BTSYNC_COOKIE" ]]; then
      __exit "unable to get cookie"
    else
      ${__BTSYNC_ECHO:-echo} "{\"cookie\": \"$BTSYNC_COOKIE\", \"at\": $__now}"
    fi
  else
    ${__BTSYNC_ECHO:-echo} "{\"cookie\": \"$BTSYNC_COOKIE\"}, \"at\": $__now}"
  fi
}

token_get() {
  BTSYNC_TOKEN="${1:-$BTSYNC_TOKEN}"
  if [[ -z "$BTSYNC_TOKEN" ]]; then
    export BTSYNC_TOKEN="$(__token_get)"
    if [[ -z "$BTSYNC_TOKEN" ]]; then
      __exit "unable to get token"
    else
      ${__BTSYNC_ECHO:-echo} "{\"token\": \"$BTSYNC_TOKEN\", \"at\": $__now}"
    fi
  else
    ${__BTSYNC_ECHO:-echo} "{\"token\": \"$BTSYNC_TOKEN\"}, \"at\": $__now}"
  fi
}

folder_get() {
  local _discovery="$(__input_fetch discovery | __zero_or_one 1)"
  local _dir="$(__input_fetch dir)"
  local _key="$(__input_fetch key)"

  if [[ -n "$_key" ]]; then
    __folder_get_single -k "$_key"
  elif [[ -n "$_dir" ]]; then
    __folder_get_single "$_dir"
  else
    __curl "getsyncfolders&discovery=$_discovery"
  fi
}

raw_get() {
  __curl "$@"
}

setting_get() {
  __curl "$(__version_selector getsettings settings)"
}

os_type_get() {
  __curl "$(__version_selector getostype getsysteminfo)"
}

# See also `webui.js#makeVersion`
version_get() {
  __curl "$(__version_selector getversion version)" \
  | perl -e '
      use JSON;
      my $json = decode_json(<>);
      my $version = $json->{"version"} || $json->{"value"};
      my $major = ($version & 0xFF000000) >> 24;
      my $minor = ($version & 0x00FF0000) >> 16;
      my $tiny = ($version & 0x0000FFFF);
      printf "{\"version\": \"%s.%s.%s\", \"major\": %s, \"minor\": %s, \"tiny\": %s}\n", $major, $minor, $tiny, $major, $minor, $tiny;
    '
}

# Note: the first match wins!!!
folder_delete() {
  local _dir=
  local _key=

  __debug "$FUNCNAME: __BTSYNC_PARAMS => $__BTSYNC_PARAMS"

  _dir="$(__folder_get_name_and_key)"
  if [[ "$_dir" == "|" ]]; then
    __exit "Folder not exist"
  else
    _key="${_dir##*|}"
    _dir="$(echo -n "${_dir%%|*}" | __url_encode)"
    if [[ -n "$_key" && -n "$_dir" ]]; then
      # FIXME: `name=` may be changed to `path=` in the future
      __curl "removefolder&name=$_dir&secret=$_key"
    else
      __exit "Your key/path is not valid"
    fi
  fi
}

folder_setting_get() {
  local _dir=
  local _key=

  _dir="$(__folder_get_name_and_key)"
  if [[ "$_dir" == "|" ]]; then
    __curl "getfoldersettings"
  else
    _key="${_dir##*|}"
    _dir="$(echo -n "${_dir%%|*}" | __url_encode)"
    if [[ -n "$_key" && -n "$_dir" ]]; then
      __curl "$(__version_selector getfolderpref folderpref)&name=$_dir&secret=$_key"
    else
      __exit "Your key/path is not valid"
    fi
  fi
}

# NOTE: `btsync` doesn't check for duplication
folder_host_create() {
  local _dir=
  local _key=
  local _addr="$(__input_fetch host)"
  local _port="$(__input_fetch port)"

  echo "$_addr" | grep -q ":"
  if [[ $? -eq 0 ]]; then
    _port="${_addr##*:}"
    _addr="${_addr%%:*}"
  fi

  if [[ -z "$_addr" || -z "$_port" ]]; then
    __exit "Port/Host must be specified"
  fi

  _dir="$(__folder_get_name_and_key)"
  if [[ "$_dir" == "|" ]]; then
    __exit "Folder path or key must be specified"
  else
    _key="${_dir##*|}"
    _dir="$(echo -n "${_dir%%|*}" | __url_encode)"
    if [[ -n "$_key" && -n "$_dir" ]]; then
      __curl "$(__version_selector addknownhosts addknownhost)&name=$_dir&secret=$_key&addr=$_addr&port=$_port" \
        | __debug_cat "$FUNCNAME/host/add"
      folder_host_get
    else
      __exit "Your key/path is not valid"
    fi
  fi
}

# NOTE: `btsync` doesn't check for duplication
folder_host_delete() {
  local _dir=
  local _key=
  local _addr="$(__input_fetch host)"
  local _port="$(__input_fetch port)"

  echo "$_addr" | grep -q ":"
  if [[ $? -eq 0 ]]; then
    _port="${_addr##*:}"
    _addr="${_addr%%:*}"
  fi

  if [[ -z "$_addr" || -z "$_port" ]]; then
    __exit "Port/Host must be specified"
  fi

  _dir="$(__folder_get_name_and_key)"
  if [[ "$_dir" == "|" ]]; then
    __exit "Folder path or key must be specified"
  else
    _key="${_dir##*|}"
    _dir="$(echo -n "${_dir%%|*}" | __url_encode)"
    if [[ -n "$_key" && -n "$_dir" ]]; then
      while :; do
        _index="$( \
          folder_host_get \
          | perl -e '
              use JSON;
              my $check = shift(@ARGV);
              my $json = decode_json(<>);
              my $hosts;
              if ($ENV{"BTSYNC_VERSION"} eq "1.3") {
                $hosts = $json->{"hosts"};
              }
              else {
                $hosts = $json->{"value"};
              }
              for (keys @{$hosts}) {
                my $h = $hosts->[$_];
                if ($check eq $h->{"peer"}) {
                  print $h->{"index"} . "\n";
                  exit(0);
                }
              }
            ' -- "$_addr:$_port"
          )"
        if [[ -z "$_index" ]]; then
          break
        fi

        __curl "removeknownhosts&name=$_dir&secret=$_key&index=$_index" \
          | __debug_cat "$FUNCNAME/host/delete $_addr:$_port, index $_index"
      done

      folder_host_get
    else
      __exit "Your key/path is not valid"
    fi
  fi
}

folder_setting_update() {
  local _dir=
  local _key=
  local _type=":N"

  [[ "$BTSYNC_VERSION" == "1.4" ]] && _type=":B"

  local _relay="$(__input_fetch   relay   | __zero_or_one $_type 0)"
  local _tracker="$(__input_fetch tracker | __zero_or_one $_type 0)"
  local _lan="$(__input_fetch     lan     | __zero_or_one $_type 1)"
  local _dht="$(__input_fetch     dht     | __zero_or_one $_type 0)"
  local _trash="$(__input_fetch   trash   | __zero_or_one $_type 1)"
  local _host="$(__input_fetch    host    | __zero_or_one $_type 1)"

  _dir="$(__folder_get_name_and_key)"
  if [[ "$_dir" == "|" ]]; then
    __exit "Key/Path must be specified"
  else
    _key="${_dir##*|}"
    _dir="$(echo -n "${_dir%%|*}" | __url_encode)"
    if [[ -n "$_key" && -n "$_dir" ]]; then
      __curl "setfolderpref&name=$_dir&secret=$_key&usehosts=$_host&relay=$_relay&usetracker=$_tracker&searchlan=$_lan&searchdht=$_dht&deletetotrash=$_trash" \
        | __debug_cat "$FUNCNAME/folder/pref/set"

      folder_setting_get
    else
      __exit "Your key/path is not valid"
    fi
  fi
}

folder_host_get() {
  local _dir=
  local _key=

  _dir="$(__folder_get_name_and_key)"
  if [[ "$_dir" == "|" ]]; then
    __exit "Key/Path must be specified"
  else
    _key="${_dir##*|}"
    _dir="$(echo -n "${_dir%%|*}" | __url_encode)"
    if [[ -n "$_key" && -n "$_dir" ]]; then
      __curl "$(__version_selector getknownhosts knownhosts)&name=$_dir&secret=$_key"
    else
      __exit "Your key/path is not valid"
    fi
  fi
}

# Generate a key-pair, or generate a ro.key from rw.key.
#
# For encryption support, please read the following article
#   http://antimatrix.org/BTSync/BTSync_Notes.html#encrypted_folders
#
# Type of keys
#
#   Axxx    RW
#   Dxxx    ERW   (encryption support, read-write)
#   Bxxx    RO
#   Exxx    RO    (un-encrypted folder folder, read-only)
#   Fxxx    ERO   (encrypted RO folder)
#
# Behavior
#
#   1. <key> is empty
#
#     <encrypt=0>   generate new keypair, print {RW, RO} keys
#     <encrypt=1>
#       <master=0>  genereate new keypair, print the RW key
#       <master=1>  genereate new keypair, push the ERW key
#                   fetch the ERO key, print {RW, RO, ERO} keys
#
#   3. <key> is RW or RO
#
#       Select <key>'s prefix and update <encrypt> and <master>
#         {ERW}, {RW} key => <nothing>
#         {ERO}, {RO} key => <encrypt> = <master> = 0
#                            (we can't get private key from a public key)
#
#      <encrypt=1>
#        <master=1> print the key, with new prefix {A -> D}
#        <master=0> change prefix, push the ERW key,
#                   fetch ERO, RO key, print {RW, RO, ERO} keys
#
#     <encrypt=0>
#       <master=1>  print the key (don't change anything!!!)
#       <master=0>  push the key and get/print {RW, RO} keys
#
key_get() {
  local _key="$(__input_fetch key)"
  local _encrypt="$(__input_fetch encrypt | __zero_or_one 0)"
  local _master="$(__input_fetch master)"

  if [[ "${_key:0:1}" == "D" ]]; then
    _encrypt=1
  fi

  if [[ "${_key:0:1}" == "A" || "${_key:0:1}" == "D" ]]; then
    __debug "$FUNCNAME: key '$_key' is a (E)RW key"
  elif [[ -n "${_key}" ]]; then
    _encrypt=0
    _master=0
    echo "{\"read_only\": \"$_key\"}"
    return
  fi

  # Generate a new key-pair and return
  if [[ -z "$_key" ]]; then
    if [[ "$_encrypt" == 0 ]]; then
      __curl "generatesecret" \
      | perl -e '
          use JSON;
          my $json = decode_json(<>);
          printf "{\"read_write\": \"%s\", \"read_only\": \"%s\"}\n",
            $json->{"secret"} || $json->{"value"}->{"secret"},
            $json->{"rosecret"} || $json->{"value"}->{"rosecret"};
        '
      return
    fi

    _key="$( \
      __curl "generatesecret" \
      | perl -e '
          use JSON;
          my $json = decode_json(<>);
          printf "%s\n", $json->{"secret"} || $json->{"value"}->{"secret"};
        '
      )"

    __debug "$FUNCNAME: primary key => $_key"

    echo "$_key" | grep -Esq '^[A-Z2-7]{33}$'
    if [[ $? -ge 1 ]]; then
      __exit "Unable to generate a random key (the first phase)"
    fi
  fi

  if [[ "$_encrypt" == 1 ]]; then
    _key="D${_key:1:33}"
  fi

  if [[ "$_master" == "1" ]]; then
    echo "{\"read_write\": \"${_key%%|*}\"}"
    return
  fi

  _key="$(__key_push_and_pull $_key)"
  if [[ "$_key" == "|" ]]; then
    __exit "Unable to generate new key. Your key may not be valid."
  else
    _rokey="${_key##*|}"
    _key="${_key%%|*}"
    if [[ -z "$_rokey" ]]; then
      _rokey="$_key"
    fi
    if [[ "$_encrypt" == 1 ]]; then
      _erokey="F${_rokey:1:32}"
      echo "{\"read_write\": \"${_key%%|*}\", \"read_only\": \"${_rokey}\", \"encryption\": \"${_erokey}\"}"
    else
      echo "{\"read_write\": \"${_key%%|*}\", \"read_only\": \"${_rokey}\"}"
    fi
  fi
}

key_onetime_get() {
  local _dir=
  local _key=

  _dir="$(__folder_get_name_and_key)"
  if [[ "$_dir" == "|" ]]; then
    __exit "Key/Path must be specified"
  else
    _key="${_dir##*|}"
    _dir="$(echo -n "${_dir%%|*}" | __url_encode)"
    if [[ -n "$_key" && -n "$_dir" ]]; then
      __curl "generateroinvite&name=$_dir&secret=$_key"
    else
      __exit "Your key/path is not valid"
    fi
  fi
}

os_dir_create() {
  local _dir

  __debug "$FUNCNAME: create on remote => $__BTSYNC_PARAMS"

  _dir="$(__input_fetch_dir)" \
  || { echo "$_dir"; exit 1; }

  __curl "adddir&dir=$_dir"
}

folder_create() {
  local _dir
  local __tmp
  local _key

  __debug "$FUNCNAME: __BTSYNC_PARAMS => $__BTSYNC_PARAMS"

  if [[ "$BTSYC_VERSION" == "1.4" ]]; then
    _dir="$(__input_fetch dir)"
  else
    _dir="$(os_dir_create)"

    __tmp="$( \
      echo "$_dir" \
      | perl -e '
          use JSON;
          my $dir = decode_json(<>);
          my $path = $dir->{"path"};
          if ($path) {
            print $path;
          }
          else {
            exit(1);
          }
        '
      )"

    if [[ -z "$__tmp" ]]; then
      echo "$_dir"
      exit
    fi
  fi

  _dir="$(echo -n "$__tmp" | __url_encode)"

  _key="$(export __BTSYNC_PARAMS="$__BTSYNC_PARAMS###master=1"; __input_fetch_key)"
  if [[ "$?" -ge 1 ]]; then
    __exit "Unable to read/create secret key."
  fi

  __tmp="$(__curl "addsyncfolder&new=1&secret=$_key&${__BTSYNC_DIR_ATTR}=$_dir")"
  echo "$__tmp" \
  | perl -e '
      use JSON;
      my $output = decode_json(<>);
      if ($output->{"error"} ne "0") {
        exit 1;
      }
    '

  if [[ $? -ge 1 ]]; then
    echo "$__tmp"
  else
    echo "$__tmp"
  fi
}

speed_get() {
  folder_get \
  | perl -e '
      use JSON;
      my $jS0n = do { local $/; <STDIN> };
      my $json = decode_json( $jS0n );
      my $recv_speed = $json->{"recv_speed"};
      my $send_speed = $json->{"send_speed"};
      my $speed = $json->{"speed"};
      if (ref($speed) eq "HASH" ) {
        printf "{\"up_speed\": \"%s\", \"down_speed\": \"%s\"}\n",
          $speed->{"upspeed"}, $speed->{"downspeed"};
      }
      else {
        printf "{\"down_speed\": \"%s\", \"up_speed\": \"%s\"}\n",
          $recv_speed, $send_speed;
      }
  '
}

license_update() {
  __curl "$(__version_selector accept setlicenseagreed)&value=true"
}

## main routine

__perl_check
__version_detect

__method="${1:-}" ; shift
__method="$(__validate_method $__method)" \
  || __exit "unknown method '$__method'"

for u in "$@"; do
  __BTSYNC_PARAMS="$u###$__BTSYNC_PARAMS"
done
export __BTSYNC_PARAMS="${__BTSYNC_PARAMS%###*}"

__BTSYNC_ECHO=: cookie_get || exit 1
__BTSYNC_ECHO=: token_get || exit 1

$__method "$@"
