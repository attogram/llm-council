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
#  Specify which models to use:
#    ./council.sh -m model1,model2,model3
#
#  Set Timeout: (number of seconds to wait for model response)
#    ./council.sh -t 30

NAME="llm-council"
VERSION="2.6"
URL="https://github.com/attogram/llm-council"

CONTEXT_SIZE="1000" # number of lines in the context
DEBUG_MODE=0        # Debug mode. 1 = debug on, 2 = debug off
TIMEOUT="20"        # number of seconds to wait for model response

# Color scheme
COLOR_RESPONSE_1=$'\e[30m\e[47m' # black text, white background
COLOR_RESPONSE_2=$'\e[37m\e[40m' # white text, black background
COLOR_SYSTEM=$'\e[37m\e[44m'     # white text, blue background
COLOR_DEBUG=$'\e[30m\e[43m'      # black text, yellow background
TEXT_NORMAL=$'\e[22m'            # Reset all formatting
TEXT_BOLD=$'\e[1m'               # Bold text
COLOR_RESET=$'\e[0m'             # Reset terminal colors
response_toggle=0                # Track alternating response colors

debug() {
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo -e "${COLOR_DEBUG}[DEBUG][$(date '+%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
  fi
}

usage() {
  me=$(basename "$0")
  echo "$NAME"; echo
  echo "Usage:"
  echo "  ./$me [flags]"
  echo "  ./$me [flags] [topic]"
  echo; echo "Flags:";
  echo "  -h       -- Help for $NAME"
  echo "  -m model1,model2  -- Use specific models (comma separated list)"
  echo "  -t #     -- Set timeout, in seconds"
  echo "  -v       -- Show version information"
  echo "  [topic]  -- Set the chat room topic (\"Example topic\")"
}

setInstructions() {
  chatInstructions="You are in a group chat room. You are user <$model>.
Review the Chat Log below, then respond to the group.
You MUST limit your response to 100 words or less. Be concise.
If mentioning other users, you MUST use syntax: @username.
To set a new topic, send ONLY the command: /topic <new topic>
To leave the chat room, send ONLY the command: /quit <optional reason>

Chat Log:
"
  debug "chatInstructions: ${chatInstructions}${context}\n-------"
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
      -h) # help
        usage
        exit 0
        ;;
      -m) # specify models to run
        validateAndSetArgument "$1" "$2" "modelsList"
        shift 2
        ;;
      -t) # set timeout
        validateAndSetArgument "$1" "$2" "TIMEOUT"
        shift 2
        ;;
      -v) # version
        echo "$NAME v$VERSION"
        exit 0
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
  if [ -n "$modelsList" ]; then
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
    models=("${parsedModels[@]}")
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

addToContext() {
  # Set up formatting variables
  local message="$1"
  # Add to context without formatting
  context+="\n${message}"
  context=$(echo "$context" | tail -n "$CONTEXT_SIZE") # get most recent $CONTEXT_SIZE lines of chat log
  local display_text=""
  # Apply bold formatting to model names at start of lines
  if [[ "$message" =~ ^'<'[^'>']+'>' ]]; then
    local model_part=${BASH_REMATCH[0]}
    local rest_of_line=${message#$model_part}
    if [ $response_toggle -eq 0 ]; then
      display_text="${COLOR_RESPONSE_1}${TEXT_BOLD}${model_part}${TEXT_NORMAL}${COLOR_RESPONSE_1}${rest_of_line}${COLOR_RESET}"
      response_toggle=1
    else
      display_text="${COLOR_RESPONSE_2}${TEXT_BOLD}${model_part}${TEXT_NORMAL}${COLOR_RESPONSE_2}${rest_of_line}${COLOR_RESET}"
      response_toggle=0
    fi
    echo -e "$display_text"
  else
    # No model part, is system message
    if [ $response_toggle -eq 0 ]; then
      echo -e "${COLOR_SYSTEM}${message}${COLOR_RESET}"
      response_toggle=1
    else
      echo -e "${COLOR_SYSTEM}${message}${COLOR_RESET}"
      response_toggle=0
    fi
  fi
}

runCommandWithTimeout() {
  ollama run "${model}" --hidethinking -- "${chatInstructions}${context}" 2>/dev/null &
  pid=$!
  (
    sleep "$TIMEOUT"
    echo "[ERROR: <$model> Timeout after ${TIMEOUT} seconds]"
    if kill -0 $pid 2>/dev/null; then
      kill $pid 2>/dev/null
    fi
  ) &
  wait_pid=$!
  wait $pid 2>/dev/null
  kill $wait_pid 2>/dev/null
}

roundList() {
  printf "<%s> " "${round[@]}"
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
  changeNotice="*** <$model> changed topic to: $1"
  topic="$1"
  setInstructions
  addToContext "$changeNotice"
}

handleCommands() {
  # Remove leading/trailing whitespace and check if it matches /topic pattern
  local trimmedResponse=$(echo "$response" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ "$trimmedResponse" =~ ^/topic[[:space:]]+(.+)$ ]]; then  
    setNewTopic "${BASH_REMATCH[1]}"
    return 1;
  elif [[ "$trimmedResponse" = "/quit" ]]; then
    quitChat "$model"
    return 1;
  elif [[ "$trimmedResponse" =~ ^/quit[[:space:]]+(.+)$ ]]; then
    quitChat "$model" "${BASH_REMATCH[1]}"
    return 1;
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

export OLLAMA_MAX_LOADED_MODELS=1
parseCommandLine "$@"

echo "${COLOR_SYSTEM}
▗▖   ▗▖   ▗▖  ▗▖     ▗▄▄▖ ▗▄▖ ▗▖ ▗▖▗▖  ▗▖ ▗▄▄▖▗▄▄▄▖▗▖
▐▌   ▐▌   ▐▛▚▞▜▌    ▐▌   ▐▌ ▐▌▐▌ ▐▌▐▛▚▖▐▌▐▌     █  ▐▌
▐▙▄▄▖▐▙▄▄▖▐▌  ▐▌    ▝▚▄▄▖▝▚▄▞▘▝▚▄▞▘▐▌ ▝▜▌▝▚▄▄▖▗▄█▄▖▐▙▄▄▖

$NAME v$VERSION${COLOR_RESET}"
echo
setModels
startRound
echo "${COLOR_SYSTEM}[SYSTEM] ${#models[@]} models in chat: $(roundList)${COLOR_RESET}";
echo "${COLOR_SYSTEM}[SYSTEM] TIMEOUT: ${TIMEOUT} seconds${COLOR_RESET}"; echo
setTopic
context=""
addToContext "*** Topic: $topic"
while true; do
  model="${round[0]}" # Get first speaker from round
  round=("${round[@]:1}") # Remove speaker from round
  if [ ${#round[@]} -eq 0 ]; then # If everyone has spoken, then restart round
    startRound
  fi
  debug "model: <$model>, round: <$(printf '%s> <' "${round[@]}" | sed 's/> <$//')>"
  setInstructions
  response=$(runCommandWithTimeout)
  if [ -z "${response}" ]; then
    response="[ERROR: No response from <${model}>]"
  fi
  handleCommands && addToContext "<$model> $response"
done
