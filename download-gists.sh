#!/bin/bash
# AUTHOR: martinrizzo@gmail.com
# DESC:   Bash script to download all gists owned by a user

# CONSTANTS (can be modified by the arguments passed to the script)
AllowSpacesInDir=false   # true = allow spaces in directory names
AllowDotsInDir=false     # true = allow dots in directory names
MaxDirLength=64          # maximum directory length (0 = no limit)
OutputDir='.'
DryRun=
UserName=
UserDir=
Command='clone_user_gists'
ScriptName=${0##*/}
ScriptVersion=0.1
Red='\033[1;31m'
Green='\033[1;32m'
Defcol='\033[0m'

# COMMANDS USED IN THIS SCRIPT
ExternCommands='test read grep sed curl git'

#=========================== MAIN SCRIPT COMMANDS ===========================#

function show_help() {
cat <<-HELP

Usage:
  $ScriptName [OPTIONS] USER

Downloads all gists for a specific user.

Options:
    -n, --dry-run   Do not actually run any commands; just print them.
    -l, --list      List the user gists
    -X              Print detailed info about each gist

    -h, --help      Print this help
    -V, --version   Print script version

HELP
}

function print_version() {
    echo "$ScriptName $ScriptVersion/n"
}

function fatal_error() {
    echo -e "${Red}ERROR:${Defcol}" "${1:-$Error}" >/dev/stderr
    exit ${2:1}
}

function list_user_gists() {
    for_each_gist_owned_by "$UserName" print_gist_name
}

function detail_user_gists() {
    for_each_gist_owned_by "$UserName" print_gist_details
}

function clone_user_gists() {
    for_each_gist_owned_by "$UserName" clone_gist
}

#============================== FOR EACH GIST ===============================#

## Functions to be used with 'for_each_gist_owned_by'
##
## @param index         Position of the gist within the list
## @param directory     The local directory where clone the gist
## @param description   A text describing the gist
## @param html_url      The URL of the gist page on GitHub
## @param git_pull_url  The URL to pull/clone the gist
##
function clone_gist() {
    local index=$1 directory=$2 description=$3 html_url=$4 git_pull_url=$5
    $DryRun git clone "$git_pull_url" "$directory"
}
function print_gist_name() {
    local index=$1 directory=$2 description=$3 html_url=$4 git_pull_url=$5
    if [ "$description" = '""' ]; then
        description=$html_url
    fi
    printf "%3d: " $index; echo "$description"
}
function print_gist_details() {
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
function for_each_gist_owned_by() {
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

#=================================== MISC ===================================#

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
function proc_gist_properties() {
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

function generate_dir() {
    local dirfilter=$1 description=$2 html_url=$3

    local directory=$(sed "$dirfilter" <<<"$description")
    local alphachars=$(sed 's/^A-Za-z0-9//g' <<<"$directory")
    [ ${#alphachars} -lt 5 ] && directory=$(sed "s/^.*:\/\///;$dirfilter" <<<"$html_url")
    echo "${OutputDir}/$directory"
}

#================================== START ===================================#

while test $# -gt 0; do
    case "$1" in
        -n | --dry-run)
          DryRun=echo
          ;;
        -l | --list)
          Command='list_user_gists'
          ;;
        -X)
          Command='detail_user_gists'
          ;;
        -h | --help)
          Command='show_help'
          ;;
        -v | --version)
          Command='print_version'
          ;;
        -*)
          Command='fatal_error';Error="Unknown option '$1'"
          ;;
        *)
          if   [ -z "$UserName"    ]; then
               UserName=$1
          elif [ -z "$UserDir" ]; then
               UserDir=$1
          else
              Command='fatal_error';Error="Unsupported extra argument '$1'"
          fi
          ;;
    esac
    shift
done

# update output directory
OutputDir=${UserDir:-$OutputDir}
OutputDir=${OutputDir%/}

# verify output directory exist
[ ! -d "$OutputDir" ] && fatal_error "Directory '$OutputDir' does not exist"

# execute script command
"$Command"
