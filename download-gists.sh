#!/bin/bash
#  Bash script to download all gists owned by a user
#  https://github.com/martin-rizzo/GitHubClonator
#  by Martin Rizzo
ScriptName=${0##*/};ScriptVersion=0.1
Help="
Usage: $ScriptName [OPTIONS] USERNAME [DIR]

Downloads all gists for a specific user.

Options:
  -s, --ssh       Clone gists using ssh (SSH keys must be configured)
  -n, --dry-run   Do not actually run any commands; just print them.
  -l, --list      List user gists
  -d, --debug     List user gists with detailed info
  -j, --json      Print the raw JSON containing the gists details

  -h, --help      Print this help
  -v, --version   Print script version
        
Examples:
  $ScriptName -l martin-rizzo   List all public gists owned by martin-rizzo
  $ScriptName martin-rizzo      Clone all public gists owned by martin-rizzo
"

# CONSTANTS (can be modified by the arguments passed to the script)
AllowSpacesInDir=false   # true = allow spaces in directory names
AllowDotsInDir=false     # true = allow dots in directory names
MaxDirLength=64          # maximum directory length (0 = no limit)
UserDir=
OutputDir='.'
DryRun=
UserName=
UserToken=
Command='clone_all_gists'
Red='\033[1;31m'
Green='\033[1;32m'
Defcol='\033[0m'

# COMMANDS USED IN THIS SCRIPT
ExternCommands='test read grep awk sed git'

#============================== MAIN COMMANDS ==============================#

show_help() { echo "$Help"; }

print_version() { echo "$ScriptName v$ScriptVersion"; }

fatal_error() {
    echo -e "${Red}ERROR:${Defcol}" "${1:-$Error}" >/dev/stderr; exit ${2:1}
}

clone_all_gists() {
    [ -z "$UserName" ] && show_help && exit 0
    for_each_gist_owned_by "$UserName" clone_gist
}

ssh_clone_all_gists() {
    [ -z "$UserName" ] && fatal_error 'Missing USERNAME parameter'
    for_each_gist_owned_by "$UserName" ssh_clone_gist
}

enumerate_all_gists() {
    [ -z "$UserName" ] && fatal_error 'Missing USERNAME parameter'
    for_each_gist_owned_by "$UserName" enumerate_gist
}

debug_all_gists() {
    [ -z "$UserName" ] && fatal_error 'Missing USERNAME parameter'
    for_each_gist_owned_by "$UserName" debug_gist
}

#============================== FOR EACH GIST ==============================#

## Group of funtions to be used with 'for_each_gist_owned_by'
##
## @param index         Position of the gist within the list
## @param directory     The local directory where clone the gist
## @param description   A text describing the gist
## @param html_url      The URL of the gist page on GitHub
## @param git_pull_url  The URL to pull/clone the gist
##
clone_gist() {
    local index=$1 directory=$2 description=$3 html_url=$4 git_pull_url=$5
    $DryRun git clone "$git_pull_url" "$directory"
}
ssh_clone_gist() {
    local index=$1 directory=$2 description=$3 html_url=$4 git_pull_url=$5
    local ssh_url=$(sed "s/^.*:\/\//git@/;s/\//:/" <<<"$git_pull_url")
    $DryRun git clone "$ssh_url" "$directory"
}
enumerate_gist() {
    local index=$1 directory=$2 description=$3 html_url=$4 git_pull_url=$5
    if [ "$description" = '""' ]; then
        description=$html_url
    fi
    printf "%3d: " $index; echo "$description"
}
debug_gist() {
    local index=$1 directory=$2 description=$3 html_url=$4 git_pull_url=$5
    echo "$description"
    echo "    WEBPAGE   $html_url"
    echo "    GIT URL   $git_pull_url"
    echo "    DIRECTORY $directory"
    echo
}

## Iterate over all user's gist and execute a function on each one
##
## @param username      The username of the gist owner
## @param gistfunction  The function to execute on each gist
##
for_each_gist_owned_by() {
    local username=$1 gistfunction=$2
    local url="https://api.github.com/users/$username/gists"
    local properties

    IFS=$'\n' read -r -d '' -a properties < <( curl "$url" | \
        grep '\"html_url\"\|\"git_pull_url\"\|\"description\"' | \
        sed 's/:/\n/;s/,$//' | \
        sed 's/^[[:space:]]*//;s/[[space:]]*$//' \
        && printf '\0' )

    proc_gist_properties $gistfunction "${properties[@]}"
}

#=============================== GITHUB API ================================#

## Prints data from all gists in JSON format
## [ https://docs.github.com/en/rest/gists/gists ]
print_json_gists_data() {
    local wget
    if   hash wget &>/dev/null; then wget=( wget --quiet -O- )
    elif hash curl &>/dev/null; then wget=( curl --silent --fail --location )
    else fatal_error "curl or wget must be installed in the system"
    fi
    if [ ! -z "$UserToken" ]; then
        "${wget[@]}" \
          --header "Accept: application/vnd.github.v3+json" \
          --header "Authorization: token $UserToken"        \
          "https://api.github.com/gists"
    else
        "${wget[@]}" \
          --header "Accept: application/vnd.github.v3+json" \
          "https://api.github.com/users/$UserName/gists"
    fi    
}

#================================== MISC ===================================#

## Execute a function on every gist reported by the provided properties
##
## Properties definition starts at the second argument. The second
## argument is a property name; the third is its value; the fourth
## is the next property name; the fifth is its value; and so on in
## that orden. Only 3 properties are taken into account: "html_url",
## "git_pull_url" & "description".
##
## @param gistfunction
##     The function to execute for each gist
##
## @param properties
##     A long list of arguments in the form of name/value pair;
##     each pair represent a property in the JSON returned by github.
##
proc_gist_properties() {
    local gistfunction=$1
    local dirfilter
    local index=0
    local allowedchars
    local directory
    local description
    local html_url
    local git_pull_url

    #-- generate directory filter --------
    allowedchars='A-Za-z0-9'
    if $AllowSpacesInDir ; then
       allowedchars="${allowedchars} "
    fi
    if $AllowDotsInDir ; then
        allowedchars="${allowedchars}\."
    fi
    dirfilter='s/^"//;s/"$//;'"s/[^${allowedchars}]/_/g"
    if [ "$MaxDirLength" -gt 0 ]; then
        dirfilter="$dirfilter;s/^\(.\{$MaxDirLength\}\).*\$/\1/"
    fi

    #-- process each property -----------
    shift
    while test $# -gt 0; do
        case "$1" in
            '"html_url"')
              shift
              html_url=$(sed 's/^"//;s/"$//' <<<"$1")
              ;;
            '"git_pull_url"')
              shift
              git_pull_url=$(sed 's/^"//;s/"$//' <<<"$1")
              ;;
            '"description"')
              shift
              description=$1
              directory=$(generate_dir "$dirfilter" "$description" "$html_url")
              ;;
        esac
        if [ ! -z "$directory"   -a \
             ! -z "$description" -a \
             ! -z "$html_url"    -a \
             ! -z "$git_pull_url"   ]
        then
            ((index++))
            "$gistfunction" $index "$directory" "$description" "$html_url" "$git_pull_url"
            directory=''
            description=''
            html_url=''
            git_pull_url=''
        fi
        shift
    done
}

generate_dir() {
    local dirfilter=$1 description=$2 html_url=$3

    local directory=$(sed "$dirfilter" <<<"$description")
    local alphachars=$(sed 's/^A-Za-z0-9//g' <<<"$directory")
    [ ${#alphachars} -lt 5 ] && directory=$(sed "s/^.*:\/\///;$dirfilter" <<<"$html_url")
    echo "${OutputDir}/$directory"
}

#================================== START ==================================#

while [ $# -gt 0 ]; do
    case "$1" in
        -s | --ssh)     Command=ssh_clone_all_gists   ;;
        -n | --dry-run) DryRun=echo                   ;;
        -l | --list)    Command=enumerate_all_gists   ;;
        -d | --debug)   Command=debug_all_gists       ;;
        -j | --json)    Command=print_json_gists_data ;;
        -h | --help)    Command=show_help             ;;
        -v | --version) Command=print_version         ;;
        -*)             Command='fatal_error';Error="Unknown option '$1'" ;;
        *)
          if   [ -z "$UserName" ]; then UserName="$1"
          elif [ -z "$UserDir"  ]; then UserDir="$1"
          else Command='fatal_error';Error="Unsupported extra argument '$1'"
          fi
          ;;
    esac
    shift
done

# update UserName / UserToken
if [ "${UserName:0:2}" = gh ] && [ ${#UserName} -ge 36 ]; then
    UserToken="$UserName"
fi

# update output directory
OutputDir=${UserDir:-$OutputDir}
OutputDir=${OutputDir%/}

# verify output directory exist
[ ! -d "$OutputDir" ] && fatal_error "Directory '$OutputDir' does not exist"

# execute script command
"$Command"
