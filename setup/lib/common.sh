
initCommon() {
  local platformName=$1
  local shouldPerformMaximumSteps=$2

  if [[ -z "$platformName" ]]; then
    >&2 echo "An platform name must be specified for installation."
    >&2 echo "Possible platform names include:"
    >&2 ls -1 "$CUSTOM_DIR/platform"
    exit 1
  fi

  export PLATFORM_NAME="$platformName"
  export SETUP_DIR
  export CUSTOM_DIR
  export PLATFORM_DIR="$CUSTOM_DIR/platform/$platformName"
  if [[ ! -d "$PLATFORM_DIR" ]]; then
    >&2 echo "An installation directory does not exist for '$platformName'."
    exit 1
  fi
  export TEMP_DIR=$(mktemp -d)

  # Automatically export the variables in these files.
  set -a
  source "$SETUP_DIR/settings"
  source "$LIB_DIR/data.sh"

  # Source defined functions for system.
  local functionFile
  for functionFile in "$LIB_DIR/functions/"*; do
  [ -f "$functionFile" ] || continue
    source "$functionFile"
  done

  # Define interests while preserving existing values.
  local interestLine
  local interestVar
  local regex="([A-Z]+_INTEREST)"
  local interestLines=$(egrep -nd recurse '[\$|\{][A-Z]+_INTEREST' "$SETUP_DIR/settings" "$PLATFORM_DIR")
  for interestLine in $interestLines; do
    if [[ "$interestLine" =~ $regex ]]; then
      local interestVar=${BASH_REMATCH[1]}
      declare -g $interestVar=${!interestVar}
      export "$interestVar"
    fi
  done

  # Load a data file for each section.
  local sectionPathFrags=$(getSectionPathFrags)
  local sectionPathFrag
  for sectionPathFrag in $sectionPathFrags; do
    local sectionDataPath="$CUSTOM_DIR/${sectionPathFrag}/data.sh"
    if [[ -f "$sectionDataPath" ]]; then
      source "$sectionDataPath"
    fi
  done
  set +a

  if [[ ! -z "$shouldPerformMaximumSteps" ]]; then
    loadInstallers
    enableAllInterests
  fi
}
export -f initCommon


loadInstallers() {
  local defaultVarList=$(compgen -v | grep -E '^[A-Z]+_DEFAULT$')
  local regex="(.+)_DEFAULT$"
  local defaultVar
  local installerVar
  local section

  set -a
  for defaultVar in $defaultVarList; do
    [[ "$defaultVar" =~ $regex ]] && installerVar="${BASH_REMATCH[1]}_INSTALLER"

    local installerVal="${!installerVar}"
    local installerDefault="${!defaultVar}"

    declare -g $installerVar="${installerVal:-$installerDefault}"
  done
  set +a
}
export -f loadInstallers


clearInstallers() {
  local installVarList=$(compgen -v | grep -E '^[A-Z]+_INSTALLER$')
  local installVar

  set -a
  for installVar in $installVarList; do
    unset "$installVar"
  done
  set +a
}
export -f clearInstallers


enableAllInterests() {
  set -a

  local interestVarList=$(compgen -v | grep -E '^[A-Z]+_INTEREST$')
  local regex='^(.+)_INTEREST$'
  for interestVar in $interestVarList; do
    declare -g $interestVar=1
  done

  set +a
}
export -f enableAllInterests


disableAllInterests() {
  set -a

  local interestVarList=$(compgen -v | grep -E '^[A-Z]+_INTEREST$')
  local regex='^(.+)_INTEREST$'
  for interestVar in $interestVarList; do
    declare -g $interestVar=''
  done

  set +a
}
export -f disableAllInterests


startInstallation() {
  # Source platform functions
  local functions=$(find "$PLATFORM_DIR/functions" -maxdepth 1 -type f)
  local fscript
  for fscript in $functions; do
    source "$fscript"
  done

  echo "Obtaining sudo capabilities"
  sudo ls / > /dev/null
  if [[ $? -ne 0 ]]; then
    >&2 echo -e "FAILED to obtain sudo access"
    return 1
  fi

  local initScriptPath="$PLATFORM_DIR/init.sh"
  set -a
  source "$initScriptPath"
  set +a

  initdPrepare
  if [[ "$?" -ne 0 ]]; then
    >&2 echo -e "${COLOR_ERROR}ERROR${TEXT_RESET} in $initScriptPath"
    >&2 echo "All Installation resources are located at: $TEMP_DIR"
    return 1
  fi

  # Find all of the files that begin with two digits and sort them.
  # This searches up to one-level deep and excludes directories and
  # file which begin with a '#'.
  local scriptPathList=$(
    find "$PLATFORM_DIR/init.d" \
      -maxdepth 2 \
      -type f \
      -name "[0-9][0-9]-*" \
      -not -path "*/#*" | \
    awk -vFS=/ -vOFS=/ '{ print $NF,$0 }' | \
    sort -n -t / | \
    cut -f2- -d/
  )

  local scriptPath
  for scriptPath in $scriptPathList; do
    if [[ ! -x "$scriptPath" ]]; then
      >&2 echo -e "${COLOR_ERROR}ERROR${TEXT_RESET} in init.d script ${scriptPath}"
      >&2 echo "The script permissions are not set to executable."
      >&2 echo "All Installation resources are located at: $TEMP_DIR"
      return 1
    fi

    "$scriptPath"

    if [[ "$?" -ne 0 ]]; then
      >&2 echo -e "${COLOR_ERROR}ERROR${TEXT_RESET} in init.d script ${scriptPath}."
      >&2 echo "All Installation resources are located at: $TEMP_DIR"
      return 1
    fi
  done

  echo "All Installation resources are located at: $TEMP_DIR"
  printf "${COLOR_NOTICE}SUCCESS!\n${TEXT_RESET}"
}
export -f startInstallation


getSectionNames() {
  local sectionName
  local sectionNames
  local sectionPathFrags=$(getSectionPathFrags)
  for sectionPathFrag in $sectionPathFrags; do
    sectionName=$(basename "$sectionPathFrag")
    sectionNames="$sectionNames $sectionName"
  done

  echo $sectionNames
}
export -f getSectionNames


getSectionPathFrags() {
  local sectionPathFrags
  sectionPathFrags=$(
    cd "$CUSTOM_DIR" && \
    find section -mindepth 1 -maxdepth 2 -type d | \
    awk '!/@[a-z]+$/'
  )
  [[ $? -ne 0 ]] && return 1

  echo $sectionPathFrags
}
export -f getSectionPathFrags


readlist() {
  echo $(grep -v -e '^#' -e '^$' "$PLATFORM_DIR/lists/$1")
}
export -f readlist


# Take only the first method field.
takeMethod() {
  [[ -z "$1" ]] && echo "" || echo "$1" | cut -d: -f1
}
export -f takeMethod


takeRef() {
  echo "$1" | cut -d: -f2-
}
export -f takeRef


# Take everything after the first field.
takeRefFirst() {
  echo "$1" | cut -d: -f2
}
export -f takeRefFirst


takeRefRest() {
  echo "$1" | cut -d: -f3-
}
export -f takeRefRest


function isUrl() {
  local ref=$1
  local regex='^[a-z]+://'
  [[ "$ref" =~ $regex ]];
  return $?
}
export -f isUrl
