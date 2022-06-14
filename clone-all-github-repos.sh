#!/bin/bash
#  Bash script to clone all github repositories owned by a user
#  https://github.com/martin-rizzo/CloneAllRepos
#  by Martin Rizzo
Help="
Usage: $ScriptName [OPTIONS] USERNAME [DIR]

Clone all github repositories owned by a specific user.
A personal access token can be used as USERNAME to access private repos.

Options:
        
    -s, --ssh        Clone repos using ssh (SSH keys must be configured)
    -n, --dry-run    Do not actually run any commands; just print them
    -l, --list       List the user repositories
    -d, --debug      Print internal info about each repo

    -gt, --by-topic  Group repos in dirs based on its topics (default)
    -gl, --by-list   Group repos in dirs based on stars list
    -gn, --no-group  No group repos in directories
    
    -h, --help       Print this help
    -v, --version    Print script version
"

# CONSTANTS (can be modified by the arguments passed to the script)
MaxDirLength=64           # maximum directory length (0 = no limit)
BaseDir=                  # base directory where the repos will be stored
DryRun=                   # set this var to 'echo' to do a dry-run
UserName=                 # name used for the github user account
Command='clone_all_repos' # main command to execute
Group='--by-topic'        # method used to group repositories
ScriptName=${0##*/}       # name of this script
ScriptVersion=0.1         # version of this script
Red='\033[1;31m'          # ANSI red color
Green='\033[1;32m'        # ANSI green color
Defcol='\033[0m'          # ANSI default color

# COMMANDS USED IN THIS SCRIPT
ExternCommands='test read awk sed git'

#============================== MAIN COMMANDS ==============================#

show_help() { echo "$Help"; }

print_version() { echo "$ScriptName v$ScriptVersion"; }

fatal_error() {
    echo -e "${Red}ERROR:${Defcol}" "${1:-$Error}" >/dev/stderr ; exit ${2:1}
}

clone_all_repos() {
    [ -z "$UserName" ] && show_help && exit 0
    [ -e "${BaseDir%/}" ] && fatal_error "directory '${BaseDir%/}' already exists"
    for_each_repo_owned_by "$UserName" clone_repo
}

ssh_clone_all_repos() {
    [ -z "$UserName" ] && fatal_error 'missing USERNAME parameter'
    [ -e "${BaseDir%/}" ] && fatal_error "directory '${BaseDir%/}' already exists"
    for_each_repo_owned_by "$UserName" ssh_clone_repo
}

enumerate_all_repos() {
    [ -z "$UserName" ] && fatal_error 'missing USERNAME parameter'
    for_each_repo_owned_by "$UserName" enumerate_repo
}

debug_all_repos() {
    [ -z "$UserName" ] && fatal_error 'missing USERNAME parameter'
    for_each_repo_owned_by "$UserName" debug_repo
}

#============================== FOR EACH REPO ===============================#
#    local html_url description clone_url ssh_url

## Group of funtions to be used with 'for_each_repo_owned_by'
##
## @param index         Position of the repo within the list
## @param name          ???
## @param description   A text describing the repo
## @param directory     The local directory where the repo will be cloned
## @param html_url      The URL of the repository's page on GitHub
## @param clone_url     The web URL to clone the repo
## @param ssh_url       The code to clone the repo using SSH
##
clone_repo() {
    fatal_error "clone repository isn't supported yet"
    local index=$1 name=$2 description=$3 directory=$4 html_url=$5 clone_url=$6 ssh_url=$7
    $DryRun git clone "$git_pull_url" "$directory"
}
ssh_clone_repo() {
    fatal_error "clone repository with ssh isn't supported yet"
    local index=$1 name=$2 description=$3 directory=$4 html_url=$5 clone_url=$6 ssh_url=$7
    local ssh_url=$(sed "s/^.*:\/\//git@/;s/\//:/" <<<"$git_pull_url")
    $DryRun git clone "$ssh_url" "$directory"
}
enumerate_repo() {
    local index=$1 name=$2 description=$3 directory=$4 html_url=$5 clone_url=$6 ssh_url=$7
    printf "%3d: %-16s %s\n" $index "$name" "$description"
}
debug_repo() {
    local index=$1 name=$2 description=$3 directory=$4 html_url=$5 clone_url=$6 ssh_url=$7
    echo "$index:$name"
    echo "    directory: $directory"
    echo "    descript : $description"
    echo "    webpage  : $html_url"
    echo "    git url  : $clone_url"
    echo "    ssh url  : $ssh_url"
    echo
}

## Iterates over all user's repos and execute a function on each one
##
## @param username      The username of the repo owner
## @param repofunction  The function to execute on each repo
##
for_each_repo_owned_by() {
    local username=$1 repofunction=$2
    local properties
    
    # api documentation:
    # [ https://docs.github.com/en/rest/repos/repos#list-repositories-for-a-user ]
    
    # super quick and dirty code to parse json with awk
    # kids, don't do it at home!!!
    IFS=$'\n' read -r -d '' -a properties < <( print_varvalue_repo_data "$username" && printf '\0' )
    proc_repo_properties "$repofunction" "${properties[@]}"
}

#=================================== MISC ===================================#

## Prints data from all repositories in var/value format
print_varvalue_repo_data() {
    # super quick and dirty code to parse json with awk
    # kids, don't do it at home!!!
    print_json_repo_data "$1" | awk '
        /\{/{++s} /\"topics\"/{t=1} 
        s==1 && (/\"name\"/||/html_url/||/description/||/clone_url/||/ssh_url/) {
            sub(/^[ \t]*/,""); sub(/[ ,\t]*$/,""); sub(/\":[ \t]*/,"\"\n"); print
        }
        t==1 && /\"dir-/ {
            match($0,/\"dir-[^\"]*\"/); print "\"topic\"\n" substr($0,RSTART,RLENGTH)
        }
        /\}/{--s} /]/{t=0} s==0 { print "}" }
        '
}

## Prints data from all repositories in JSON format
print_json_repo_data() {
    local username="$1"
    local wget
    if   hash wget &>/dev/null; then wget=( wget --quiet -O- )
    elif hash curl &>/dev/null; then wget=( curl --silent --fail --location )
    else fatal_error "curl or wget must be installed in the system"
    fi
    if [ ${#username} -ge 36 ] && [ "${username:0:2}" = gh ]; then
        "${wget[@]}" \
          --header "Accept: application/vnd.github.v3+json" \
          --header "Authorization: token $username"         \
          "https://api.github.com/user/repos"
    else
        "${wget[@]}" \
          --header "Accept: application/vnd.github.v3+json" \
          "https://api.github.com/users/$username/repos"
    fi    
}

## Prints the path for the local directory where repository will be cloned
print_local_directory() {
    local name=$1 topic=$2 subdir
    case $Group in
        --by-list)  subdir="$list/" ;;
        --by-topic) [ ! -z "$topic" ] && subdir="$topic/" ;;
    esac
    echo "${BaseDir}${subdir}${name}"
}

## Executes a function on every repo reported by the provided properties
##
## Properties definition starts at the second argument. The second
## argument is a property name; the third is its value; the fourth
## is the next property name; the fifth is its value; and so on in
## that orden. Only 6 properties are taken into account: "name",
## "description", "html_url", "clone_url", "ssh_url" & "topic".
##
## @param repofunction
##     The function to execute for each repo
##
## @param properties
##     A long list of arguments in the form of name/value pair;
##     each pair represent a property in the JSON returned by github.
##
proc_repo_properties() {
    local repofunction=$1
    local index=0 topic
    local name html_url description clone_url ssh_url
    local remove_quotes='sub(/^\"/,"");sub(/\"$/,"")'
    local remove_dir_prefix='sub(/^"dir-/,"");sub(/\"$/,"")'
    local capitalize='print toupper(substr($0,0,1))tolower(substr($0,2))'

    #-- process each property -----------
    shift
    while test $# -gt 0; do
        case "$1" in
            '"name"')
              shift; name=$(awk "{$remove_quotes}1" <<<"$1")
              ;;
            '"description"')
              shift; description=$1
              ;;
            '"html_url"')
              shift; html_url=$(awk "{$remove_quotes}1" <<<"$1")
              ;;
            '"clone_url"')
              shift; clone_url=$(awk "{$remove_quotes}1" <<<"$1")
              ;;
            '"ssh_url"')
              shift; ssh_url=$(awk "{$remove_quotes}1" <<<"$1")
              ;;
            '"topic"')
              shift; topic=$(awk "{$remove_dir_prefix;$capitalize}" <<<"$1")
              ;;
            '}')
            if [ ! -z "$name" -a ! -z "$clone_url" -a ! -z "$ssh_url" ]; then
                directory=$(print_local_directory "$name" "$topic")
                ((index++))
                "$repofunction" $index "$name" "$description" "$directory" "$html_url" "$clone_url" "$ssh_url"
                name=;description=;directory=;html_url=;clone_url=;ssh_url=;topic=
            fi
        esac
        shift
    done
}

#================================== START ===================================#

while test $# -gt 0; do
    case "$1" in
        -s | --ssh)      Command=ssh_clone_all_repos ;;
        -n | --dry-run)  DryRun=echo                 ;;
        -l | --list)     Command=enumerate_all_repos ;;
        -d | --debug)    Command=debug_all_repos     ;;
        -gt| --by-topic) Group='--by-topic'          ;;
        -gl| --by-list)  Group='--by-list'           ;;
        -gn| --no-group) Group='--no-group'          ;; 
        -h | --help)     Command=show_help           ;;
        -v | --version)  Command=print_version       ;;
        -*)              Command='fatal_error';Error="unknown option '$1'" ;;
        *)
          if   [ -z "$UserName"  ]; then UserName="$1"
          elif [ -z "$BaseDir"   ]; then BaseDir="$1"
          else Command='fatal_error';Error="unsupported extra argument '$1'"
          fi
          ;;
    esac
    shift
done

# update base directory
[ -z "$BaseDir" ] && BaseDir="./$UserName/"
BaseDir=${BaseDir%/}/

# handle unimplemented options
[ "$Group" == '--by-list' ] && fatal_error "group by stars list isn't implemented yet"

# execute script command
"$Command"
