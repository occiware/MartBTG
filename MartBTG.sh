#!/usr/bin/env bash

# ##################################################
# Model@RunTime Bash Template Generator
# ##################################################
#
# Generates files from a given template by swapping
# its variables with values found on a given
# martserver instance (or in a config file
# containing default values).
#
# Boilerplate code from Nate Landau:
# https://github.com/natelandau/shell-scripts
#
version="1.0.1"              # Sets version variable
#
# CURRENTLY ONLY SUPPORTS APT FOR AUTOMATIC
# DEPENDENCY INSTALLATION.
#
# Dependencies:
# - jq for parsing json files
# - curl to transfer data from a server
dependencies=( jq curl )
#
# HISTORY:
#
# * 2017/07/14 - v1.0.0  - First fully functional version
# * 2017/07/17 - v1.0.1  - Add documentation & Additionnal checks
#
# ##################################################

# Default MartServer username
defaultUsername="admin"
# Default MartServer password
defaultPASS="1234"

function mainScript() {
    # Check if provided template file exists, if not, die
    if [ ! -f "$template" ]
    then
        die "Either you forgot to specify a template file, either the one you specified doesn't exist."
    fi

    # If the user did not provide either a config file or a URI
    if [ ! -f "$config" ] && [ -z ${resource+x} ]
    then
        die "You cannot fill in a template with no resource URI or configuration file."
    fi

    # Create temporary output and config files
    cp $template $tmpOutput

    # Check if a resource URI has been provided, and if so, fetch the content
    # Otherwise, log that since no URI has been, set, we will try using only
    # the config file
    if [ ! -z ${resource+x} ]; then
        # Check if $resource is a URL, else die
        checkIfValidURLRegex='(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
        if [[ $resource =~ $checkIfValidURLRegex ]]
        then
            verbose "The Resource URI seems valid: $resource"
        else
            die "The Resource provided ($resource) is not a valid URL."
        fi

        # Check if $username AND $PASS are set together, or not set at all
        # If only one is defined, die
        if [ -z ${username+x} ] || [ -z ${PASS+x} ]; then
            if [ -z ${username+x} ] && [ -z ${PASS+x} ]; then
                # Fetch config from the ressource and save it to tmpResource
                verbose $(curl -X GET "$resource" -H 'accept: application/json' -u "$username":"$PASS" -o "$tmpResource" 2>&1)
            else
                die "You forgot to either set the username or the password."
            fi
        else
            verbose "No username and password provided: falling back to defaults"
            verbose $(curl -X GET "$resource" -H 'accept: application/json' -u "$defaultUsername":"$defaultPASS" -o "$tmpResource" 2>&1)
        fi

        # If we couldn't create the resource file, die
        if [ ! -f "$tmpResource" ]
        then
            die "The resource couln't be transferred from the remote server. Please check that the URI you provided actually returns a valid JSON file."
        fi

        # Flatten the json and savee the result in tmpResourceFlattened
        jq '. as $in | reduce leaf_paths as $path ({}; . + { ($path | map(tostring) | join(".")): $in | getpath($path) })' $tmpResource > $tmpResourceFlattened
    else
        verbose "No Resource URI has been provided: trying to use the config file only."
    fi

    # Get all variables in template (anyhting between "${" and "}")
    variables=($(grep -oP '\$\{\K[^\}]+' "$template"))

    # Declare associative array (hashmap for bash)
    declare -A variablesMap

    # For every variable found, associate it with its default value in the config file
    # Then, try to override the value if it exists in the previously fetched config
    for variable in "${variables[@]}"
    do
        # Check if provided template file exists
        if [ ! -f "$config" ]
        then
            verbose "If you specified a config file, it doesn't exist."
        else
            # If the config file exists, associate the variable with its default
            # value in the config file. If no value is found, set to "null".
            value=$(grep -oP "${variable}=\"\K[^\"]+" "$config"||true)
            if [[ !  -z  $value  ]]; then
                variablesMap[${variable}]=$value
            else
                variablesMap[${variable}]="null"
            fi
        fi

        # Override the value if and only if we find a match in the resource
        # file ($value not null)
        if [ -f "$tmpResourceFlattened" ]
        then
            value=$(jq -r ".\"${variable}\"" "$tmpResourceFlattened")
            if [ $value != "null" ]; then
                variablesMap[${variable}]=$value
            fi
        fi

        # If no value for the template variable is found in either the config or
        # resource file, die.
        if [ -z ${variablesMap[${variable}]} ] || [ ${variablesMap[${variable}]} == "null" ]; then
            die "The template variable \${${variable}} does not have a corresponding value in either the config or the resource file."
        fi

        # Replace in temporary output file all references to the variable by the matching value
        search="\${${variable}}"
        replace="${variablesMap[${variable}]}"
        searchEscaped=$(sed 's/[^^]/[&]/g; s/\^/\\^/g' <<<"$search")
        replaceEscaped=$(sed 's/[&/\]/\\&/g' <<<"$replace")

        sed -i "s/$searchEscaped/$replaceEscaped/g" $tmpOutput
    done

    # If the output file is not set, copy the temporary output file's contents
    # into the definitive one, else use standard output
    if [ ! -z ${output+x} ]; then
        cp $tmpOutput $output
    else
        cat $tmpOutput
    fi
}

hasProg() {
    [ -x "$(which $1)" ]
}

function installDeps() {
    if hasProg apt-get ; then aptInstallDeps
    # elif hasProg yum ; then yumInstallDeps
    else
        die "No supported package manager found!"
    fi
}

function aptInstallDeps {
    for dependency in "${dependencies[@]}"
    do
        if [ $(dpkg-query -W -f='${Status}' ${dependency} 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
          verbose $(sudo apt-get install ${dependency})
        fi
    done
}

function trapCleanup() {
  echo ""
  # Delete temp files, if any
  if [ -d "${tmpDir}" ] ; then
    rm -r "${tmpDir}"
  fi
  die "Exit trapped. In function: '${FUNCNAME[*]}'"
}

function safeExit() {
  # Delete temp files, if any
  if [ -d "${tmpDir}" ] ; then
    rm -r "${tmpDir}"
  fi
  trap - INT TERM EXIT
  exit
}

# Set Base Variables
# ----------------------
scriptName=$(basename "$0")

# Set Flags
quiet=false
printLog=false
verbose=false
force=false
strict=false
debug=false
args=()

# Set Colors
bold=$(tput bold)
reset=$(tput sgr0)
purple=$(tput setaf 171)
red=$(tput setaf 1)
green=$(tput setaf 76)
tan=$(tput setaf 3)
blue=$(tput setaf 38)
underline=$(tput sgr 0 1)

# Set Temp Directory
tmpDir="/tmp/${scriptName}.$RANDOM.$RANDOM.$RANDOM.$$"
(umask 077 && mkdir "${tmpDir}") || {
  die "Could not create temporary directory! Exiting."
}

# Create temporary file to hold resource information
tmpResource="${tmpDir}/tmpResource.json"
tmpResourceFlattened="${tmpDir}/tmpResourceFlattened.json"
tmpOutput="${tmpDir}/output"

# Logging
# -----------------------------------
# Log is only used when the '-l' flag is set.
logFile="${HOME}/Library/Logs/${scriptBasename}.log"

# Options and Usage
# -----------------------------------
usage() {
  echo -n "
                    ${bold}Model@RunTime Bash Template Generator${reset}

${bold}Generic Command:${reset}

${scriptName} -t <PATH_TO_TEMPLATE> -r '<RESOURCE_URI>' [OPTION]...

${bold}Description:${reset}

Generates files from a given template by swapping its variables with values
found on a given martserver instance (or in a config file containing default
values). You must at least specify a valid -t parameter (template) and a
valid URL as the -r parameter (MartServer resource).

${bold}Typical usage:${reset}

${scriptName} -t <PATH_TO_TEMPLATE> -r '<RESOURCE_URI>' -c <PATH_TO_CONFIG>
    -o <PATH_TO_OUTPUT> -u <USERNAME> -p

${bold}Options:${reset}
    -t, --template    Template file
    -c, --config      Optional config file containing default values
    -o, --output      Optional output file
    -r, --resource    MartServer resource URL
    -u, --username    Username for script. Must be used with -p.
    -p, --password    User password. Must be used with -u before.
    --force           Skip all user interaction.
    -q, --quiet       Quiet (no output)
    -l, --log         Print log to file
    -s, --strict      Exit script with null variables.  i.e 'set -o nounset'
    -v, --verbose     Output more information. (Items echoed to 'verbose')
    -d, --debug       Runs script in BASH debug mode (set -x)
    -h, --help        Display this help and exit
      --version     Output version information and exit

"
}

# Iterate over options breaking -ab into -a -b when needed and --foo=bar into
# --foo bar
optstring=h
unset options
while (($#)); do
  case $1 in
    # If option is of type -ab
    -[!-]?*)
      # Loop over each character starting with the second
      for ((i=1; i < ${#1}; i++)); do
        c=${1:i:1}

        # Add current char to options
        options+=("-$c")

        # If option takes a required argument, and it's not the last char make
        # the rest of the string its argument
        if [[ $optstring = *"$c:"* && ${1:i+1} ]]; then
          options+=("${1:i+1}")
          break
        fi
      done
      ;;

    # If option is of type --foo=bar
    --?*=*) options+=("${1%%=*}" "${1#*=}") ;;
    # add --endopts for --
    --) options+=(--endopts) ;;
    # Otherwise, nothing special
    *) options+=("$1") ;;
  esac
  shift
done
set -- "${options[@]}"
unset options

# Print help if no arguments were passed.
# Uncomment to force arguments when invoking the script
# -------------------------------------
[[ $# -eq 0 ]] && set -- "--help"

# Read the options and set stuff
while [[ $1 = -?* ]]; do
  case $1 in
    -h|--help) usage >&2; safeExit ;;
    --version) echo "$(basename $0) ${version}"; safeExit ;;
    -t|--template) shift; template=${1} ;;
    -c|--config) shift; config=${1} ;;
    -o|--output) shift; output=${1} ;;
    -r|--resource) shift; resource=${1} ;;
    -u|--username) shift; username=${1} ;;
    -p|--password) shift; echo "Enter Pass: "; stty -echo; read PASS; stty echo;
      echo ;;
    -v|--verbose) verbose=true ;;
    -l|--log) printLog=true ;;
    -q|--quiet) quiet=true ;;
    -s|--strict) strict=true;;
    -d|--debug) debug=true;;
    --force) force=true ;;
    --endopts) shift; break ;;
    *) die "invalid option: '$1'." ;;
  esac
  shift
done

# Store the remaining part as arguments.
args+=("$@")


# Logging & Feedback
# -----------------------------------------------------
function _alert() {
  if [ "${1}" = "error" ]; then local color="${bold}${red}"; fi
  if [ "${1}" = "warning" ]; then local color="${red}"; fi
  if [ "${1}" = "success" ]; then local color="${green}"; fi
  if [ "${1}" = "debug" ]; then local color="${purple}"; fi
  if [ "${1}" = "header" ]; then local color="${bold}${tan}"; fi
  if [ "${1}" = "input" ]; then local color="${bold}"; fi
  if [ "${1}" = "info" ] || [ "${1}" = "notice" ]; then local color=""; fi
  # Don't use colors on pipes or non-recognized terminals
  if [[ "${TERM}" != "xterm"* ]] || [ -t 1 ]; then color=""; reset=""; fi

  # Print to console when script is not 'quiet'
  if ${quiet}; then return; else
   echo -e "$(date +"%r") ${color}$(printf "[%7s]" "${1}") ${_message}${reset}";
  fi

  # Print to Logfile
  if ${printLog} && [ "${1}" != "input" ]; then
    color=""; reset="" # Don't use colors in logs
    echo -e "$(date +"%m-%d-%Y %r") $(printf "[%7s]" "${1}") ${_message}" >> "${logFile}";
  fi
}

function die ()       { local _message="${*} Exiting."; echo -e "$(_alert error)"; safeExit;}
function error ()     { local _message="${*}"; echo -e "$(_alert error)"; }
function warning ()   { local _message="${*}"; echo -e "$(_alert warning)"; }
function notice ()    { local _message="${*}"; echo -e "$(_alert notice)"; }
function info ()      { local _message="${*}"; echo -e "$(_alert info)"; }
function debug ()     { local _message="${*}"; echo -e "$(_alert debug)"; }
function success ()   { local _message="${*}"; echo -e "$(_alert success)"; }
function input()      { local _message="${*}"; echo -n "$(_alert input)"; }
function header()     { local _message="== ${*} ==  "; echo -e "$(_alert header)"; }
function verbose()    { if ${verbose}; then debug "$@"; fi }

# SEEKING CONFIRMATION
# ------------------------------------------------------
function seek_confirmation() {
  # echo ""
  input "$@"
  if "${force}"; then
    notice "Forcing confirmation with '--force' flag set"
  else
    read -p " (y/n) " -n 1
    echo ""
  fi
}
function is_confirmed() {
  if "${force}"; then
    return 0
  else
    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
      return 0
    fi
    return 1
  fi
}
function is_not_confirmed() {
  if "${force}"; then
    return 1
  else
    if [[ "${REPLY}" =~ ^[Nn]$ ]]; then
      return 0
    fi
    return 1
  fi
}


# Trap bad exits with your cleanup function
trap trapCleanup EXIT INT TERM

# Set IFS to preferred implementation
IFS=$' \n\t'

# Exit on error. Append '||true' when you run the script if you expect an error.
set -o errexit

# Run in debug mode, if set
if ${debug}; then set -x ; fi

# Exit on empty variable
if ${strict}; then set -o nounset ; fi

# Bash will remember & return the highest exitcode in a chain of pipes.
# This way you can catch the error in case mysqldump fails in `mysqldump |gzip`, for example.
set -o pipefail

# Install dependencies
installDeps

# Run your script
mainScript

# Exit cleanly
safeExit
