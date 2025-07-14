#!/usr/bin/env bash
#
# LLM Council
#
# A group chat room with all your Ollama models, or a selection of your models
#
# Usage:
#
#  Use all models:
#    ./council.sh
#
#  See usage help:
#    ./council.sh -h
#
#  Specify which models to use:
#    ./council.sh -m model1,model2,model3
#
#  Set Timeout: (number of seconds to wait for model response)
#    ./council.sh -t 30

NAME="llm-council"
VERSION="2.17"
URL="https://github.com/attogram/llm-council"

CHAT_LOG_LINES="500" # number of lines in the chat log
DEBUG_MODE=0 # Debug mode. 1 = debug on, 2 = debug off
TIMEOUT=20   # number of seconds to wait for model response
TEXT_WRAP=0  # Text wrap. 0 = no wrap, >0 = wrap line

usage() {
  me=$(basename "$0")
  echo "$NAME"; echo
  echo "Usage:"
  echo "  ./$me [flags]"
  echo "  ./$me [flags] [topic]"
  echo; echo "Flags:";
  echo "  -m model1,model2 -- Use specific models (comma separated list)"
  echo "  -nocolors        -- Do not use ANSI colors"
  echo "  -t #             -- Set timeout to # seconds"
  echo "  -wrap #          -- Text wrap to # characters per line"
  echo "  [topic]          -- Set the chat room topic (\"Example topic\")"
  echo "  -debug           -- Debug Mode"
  echo "  -v               -- Show version information"
  echo "  -h               -- Help for $NAME"
}

debug() {
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo -e "${COLOR_DEBUG}[DEBUG] [$(date '+%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
  fi
}

setInstructions() {
  chatInstructions="You are in a group chat room. You are user <$model>.
Review the Chat Log below, then respond to the group.
You MUST limit your response to 100 words or less. Be concise.
If mentioning other users, you MUST use syntax: @username.
To set a new topic, send ONLY the 1 line command: /topic <new topic>

Chat Log:
"
  #debug "chatInstructions:\n---\n${chatInstructions}${context}\n---"
}

yesColors() {
  COLOR_RESPONSE_1=$'\e[37m\e[48;5;233m' # white text, dark grey background
  COLOR_RESPONSE_2=$'\e[37m\e[40m'  # white text, black background
  COLOR_SYSTEM=$'\e[37m\e[48;5;17m' # white text, dark blue background
  COLOR_DEBUG=$'\e[30m\e[43m'       # black text, yellow background
  TEXT_NORMAL=$'\e[22m'             # Normal style text
  TEXT_BOLD=$'\e[1m'                # Bold style text
  COLOR_RESET=$'\e[0m'              # Reset terminal colors
  response_toggle=0                 # Track alternating response colors
}

noColors() {
  COLOR_RESPONSE_1=""
  COLOR_RESPONSE_2=""
  COLOR_SYSTEM=""
  COLOR_DEBUG=""
  TEXT_NORMAL=""
  TEXT_BOLD=""
  COLOR_RESET=""
}

validateAndSetArgument() {
  local flag=$1
  local value=$2
  local var_name=$3
  if [ -n "$value" ] && [ ${value:0:1} != "-" ]; then
    eval "$var_name='$value'"
    return 0
  else
    echo "Error: Argument for $flag is missing" >&2
    exit 1
  fi
}

parseCommandLine() {
  modelsList=""
  resultsDirectory="results"
  topic=""
  while (( "$#" )); do
    case "$1" in
      -d|-debug|--debug) # Debug Mode
        DEBUG_MODE=1
        shift
        ;;
      -h|-help|--help) # help
        usage
        exit 0
        ;;
      -nocolors|--nocolors|-nc) # No ANSI Colors
        noColors
        shift
        ;;
      -m|-models|--models) # specify models to run
        validateAndSetArgument "$1" "$2" "modelsList"
        shift 2
        ;;
      -t|-timeout|--timeout) # set timeout
        validateAndSetArgument "$1" "$2" "TIMEOUT"
        shift 2
        ;;
      -v|-version|--version) # version
        echo "$NAME v$VERSION"
        exit 0
        ;;
      -wrap|-w) # wrap lines
        validateAndSetArgument "$1" "$2" "TEXT_WRAP"
        shift 2
        ;;
      -*|--*=) # unsupported flags
        echo "Error: unsupported argument: $1" >&2
        exit 1
        ;;
      *) # preserve positional arguments
        topic+="$1"
        shift
        ;;
    esac
  done
  # set positional arguments in their proper place
  eval set -- "${topic}"
}

setModels() {
  models=($(ollama list | awk '{if (NR > 1) print $1}' | sort)) # Get list of models, sorted alphabetically
  if [ -z "$models" ]; then
    echo "No models found. Please install models with 'ollama pull <model-name>'" >&2
    exit 1
  fi
  parsedModels=()
  if [ -n "$modelsList" ]; then # If user supplied a model list with -m
    IFS=',' read -ra modelsListArray <<< "$modelsList" # parse csv into modelsListArray
    for m in "${modelsListArray[@]}"; do
      if [[ " ${models[*]} " =~ " $m " ]]; then # if model exists
        parsedModels+=("$m")
      else
        echo "Error: model not found: $m" >&2
        exit 1
      fi
    done
  fi
  if [ -n "$parsedModels" ]; then
    IFS=$'\n' sortedParsedModels=($(sort <<<"${parsedModels[*]}"))
    unset IFS
    models=("${sortedParsedModels[@]}")
  fi
  if [ ${#models[@]} -lt 1 ]; then
    echo "Error: there must be at least 1 model to chat" >&2
    exit 1
  fi
}

setTopic() {
  if [ -n "$topic" ]; then # if topic is already set from command line
    return
  fi
  if [ -t 0 ]; then # Check if input is from a terminal (interactive)
    echo "${COLOR_SYSTEM}Enter topic:${COLOR_RESET}"
    read -r topic # Read topic from user input
    echo
    return
  fi
  topic=$(cat) # Read from standard input (pipe or file)
}

systemMessage() {
  if [ ""$TEXT_WRAP -ge 1 ]; then
    echo -e "$1" | fold -s -w "$TEXT_WRAP"
  else
    echo -e "$1"
  fi
}

displayContextAdded() {
  local message="$1"
  local display_text=""
  if [[ "$message" =~ ^'<'[^'>']+'>' ]]; then #
    local model_part=${BASH_REMATCH[0]}
    local rest_of_line=${message#$model_part}
    # Apply bold formatting to <model> names at start of lines
    if [ $response_toggle -eq 0 ]; then
      display_text="${COLOR_RESPONSE_1}${TEXT_BOLD}${model_part}${TEXT_NORMAL}${COLOR_RESPONSE_1}${rest_of_line}${COLOR_RESET}"
      response_toggle=1
    else
      display_text="${COLOR_RESPONSE_2}${TEXT_BOLD}${model_part}${TEXT_NORMAL}${COLOR_RESPONSE_2}${rest_of_line}${COLOR_RESET}"
      response_toggle=0
    fi
  else
    # No model part, is a system message
    display_text="${COLOR_SYSTEM}${message}${COLOR_RESET}"
  fi
  systemMessage "$display_text"
}

addToContext() {
  local message="$1"
  context+="\n${message}" # Add raw message to context
  context=$(echo "$context" | tail -n "$CHAT_LOG_LINES") # get most recent $CHAT_LOG_LINES lines of chat log
  echo -e "$context" > ./messages.txt # LOGGING: save messages
  displayContextAdded "$message"
}

removeThinking() {
  local message="$1"
  if [[ $message == *"<think>"* ]]; then
    message=$(echo "$message" | sed '/<think>/,/<\/think>/d')
  fi
  if [[ $message == *"Thinking\.\.\."* ]]; then
    message=$(echo "$message" | sed '/Thinking\.\.\./,/\.\.\.done thinking\./d')
  fi
  echo "$message"
}

runCommandWithTimeout() {
  (
    ollama run "${model}" --hidethinking -- "${chatInstructions}${context}" 2>/dev/null
  ) &
  pidOllama=$!

  (
    sleep "$TIMEOUT"
    if kill -0 $pidOllama 2>/dev/null; then
      kill $pidOllama 2>/dev/null
    fi
  ) &
  pidOllamaTimeout=$!

  (
    exec 3</dev/tty
    stty -echo -icanon <&3
    while kill -0 $pidOllama 2>/dev/null; do # while Ollama is still running
    #while true; do
      key=$(dd bs=1 count=1 <&3 2>/dev/null) # get 1 character of user input
      #read -r -t 1 -n 1 <&3
      if [[ -n "$key" ]]; then # if got user input
        kill $pidOllamaTimeout $pidOllama 2>/dev/null
        echo "[SYSTEM-KEY-PRESS]"
        break
      fi
      sleep 0.1
    done
    stty echo icanon <&3
    exec 3<&-
  ) &
  pidKeyPress=$!

  wait $pidOllama 2>/dev/null
  kill $pidOllamaTimeout $pidKeyPress 2>/dev/null
}

quitChat() {
  local model="$1"
  local reason="$2"
  changeNotice="*** <$model> left the chat"
  if [ -n "$reason" ]; then
    changeNotice+=": $reason"
  fi
  addToContext "$changeNotice"
  # Remove the model from the models array
  local newModels=()
  for m in "${models[@]}"; do
    if [ " $m " != " $model " ]; then
      newModels+=("$m")
    fi
  done
  models=("${newModels[@]}")
  # Check if we still have enough models to continue
  if [ ${#models[@]} -lt 1 ]; then
    echo; echo "${COLOR_SYSTEM}[SYSTEM] No models remaining. Chat ending.${COLOR_RESET}"
    exit 0
  fi
}

setNewTopic() {
  addToContext "*** <$model> changed topic to: $1"
}

handleCommands() {
  local response="$1"
  # Remove leading/trailing whitespace
  local trimmedResponse=$(echo "$response" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  # check if it matches /topic pattern
  if [[ "$trimmedResponse" =~ ^/topic[[:space:]]+(.+)$ ]]; then
    setNewTopic "${BASH_REMATCH[1]}"
    return 1;
# To leave the chat room, send ONLY the command: /quit <optional reason>
#  elif [[ "$trimmedResponse" = "/quit" ]]; then
#    quitChat "$model"
#    return 1;
#  elif [[ "$trimmedResponse" =~ ^/quit[[:space:]]+(.+)$ ]]; then
#    quitChat "$model" "${BASH_REMATCH[1]}"
#    return 1;
  fi
  return 0;
}

startRound() {
  round=("${models[@]}")
  # shuffle round
  local n=${#round[@]}
  for ((i = n - 1; i > 0; i--)); do
    local j=$((RANDOM % (i + 1)))
    local temp=${round[i]}
    round[i]=${round[j]}
    round[j]=$temp
  done
  debug "startRound: <$(printf '%s> <' "${round[@]}" | sed 's/> <$//')>"
}

stopModel() {
  ollama stop "$1"
  debug "$(ollama ps)"
  debug "Stopped model: $1"
}

#trap exitCleanup INT
#
#function exitCleanup() {
#  echo; echo "Ending Chat."
#  exit
#}

export OLLAMA_MAX_LOADED_MODELS=1
yesColors
parseCommandLine "$@"
echo "${COLOR_SYSTEM}
▗▖   ▗▖   ▗▖  ▗▖     ▗▄▄▖ ▗▄▖ ▗▖ ▗▖▗▖  ▗▖ ▗▄▄▖▗▄▄▄▖▗▖
▐▌   ▐▌   ▐▛▚▞▜▌    ▐▌   ▐▌ ▐▌▐▌ ▐▌▐▛▚▖▐▌▐▌     █  ▐▌
▐▙▄▄▖▐▙▄▄▖▐▌  ▐▌    ▝▚▄▄▖▝▚▄▞▘▝▚▄▞▘▐▌ ▝▜▌▝▚▄▄▖▗▄█▄▖▐▙▄▄▖

$NAME v$VERSION"
echo
setModels
systemMessage "${#models[@]} models in the group chat room:"
systemMessage "$(printf "<%s> " "${models[@]}")"
startRound
debug "TIMEOUT: ${TIMEOUT} seconds"
debug "CHAT_LOG_LINES: ${CHAT_LOG_LINES}"
debug "TEXT_WRAP: ${TEXT_WRAP}${COLOR_RESET}"
echo
setTopic
context=""
addToContext "*** Topic: $topic"
setInstructions; echo -e "$chatInstructions" > ./instructions.txt # LOGGING: save chat instructions
while true; do
  model="${round[0]}" # Get first speaker from round
  debug "model: <$model> -- round: <$(printf '%s> <' "${round[@]}" | sed 's/> <$//')>"
  setInstructions
  response=$(runCommandWithTimeout)
  if [[ "$response" == *"[SYSTEM-KEY-PRESS]"* ]]; then
    debug "PAUSING CHAT. response: $response"
    echo; echo "Enter user input:"
    read -r userInput
    debug "USER INPUT: [$userInput]"
    echo
    model="user"
    handleCommands "$userInput" && addToContext "<user> $userInput"
    continue
  fi
  response=$(removeThinking "$response")
  stopModel "$model"
  if [ -z "${response}" ]; then
    debug "[ERROR] No response from <${model}> within $TIMEOUT seconds"
  else
    handleCommands "$response" && addToContext "<$model> $response"
  fi
  round=("${round[@]:1}") # Remove speaker from round
  if [ ${#round[@]} -eq 0 ]; then # If everyone has spoken, then restart round
    startRound
  fi
done
