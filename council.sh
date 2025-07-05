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
VERSION="2.3"
URL="https://github.com/attogram/llm-council"

CONTEXT_SIZE="750" # number of lines in the context
DEBUG_MODE=0       # Debug mode. 1 = debug on, 2 = debug off
TIMEOUT="60"       # number of seconds to wait for model response

# Color scheme
RESPONSE_BACKGROUND_1=$'\e[48;5;250m' # Light grey background color
RESPONSE_FOREGROUND_1=$'\e[38;5;0m'   # Black text color
RESPONSE_BACKGROUND_2=$'\e[48;5;245m' # Medium grey background color
RESPONSE_FOREGROUND_2=$'\e[38;5;0m'   # Black text color
DEBUG_BACKGROUND=$'\e[48;5;240m'      # background grey
DEBUG_FOREGROUND=$'\e[38;5;226m'      # foreground yellow
NORMAL_TEXT=$'\e[22m'                 # Reset all formatting
BOLD_TEXT=$'\e[1m'                    # Bold text
RESET=$'\e[0m'                        # reset terminal colors
prev_bg_toggle=0                      # Keep track of alternating background colors

debug() {
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo -e "${DEBUG_BACKGROUND}${DEBUG_FOREGROUND}[DEBUG] $1${RESET}"
    echo
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
Read the chat log below for context.
Be concise in your response. You have ${TIMEOUT} seconds to respond.
To mention other users, use syntax: '@username'.
Use your best judgment to form your own opinions. You do not have to agree with other users.
You may steer the conversation to a new topic. Send only the command: /topic <new topic>
You may leave the chat room if you want to end your participation. Send only the command: /quit <optional reason>

The current room topic is:
---
$topic
---

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
    echo "Enter topic:"
    read -r topic # Read topic from user input
    echo
    return
  fi
  topic=$(cat) # Read from standard input (pipe or file)
}

addToContext() {
  # Set up formatting variables
  local formatted=$(echo "$1" | sed '1!s/^/    /g') # From 2nd line onwards, indent every line with 4 spaces
  # Add to context without formatting
  context+="\n${formatted}"
  context=$(echo "$context" | tail -n "$CONTEXT_SIZE") # get most recent $CONTEXT_SIZE lines of chat log
  local display_text=""
  # Apply bold formatting to model names at start of lines
  if [[ "$formatted" =~ ^'<'[^'>']+'>' ]]; then
    local model_part=${BASH_REMATCH[0]}
    local rest_of_line=${formatted#$model_part}
    if [ $prev_bg_toggle -eq 0 ]; then
      display_text="${RESPONSE_BACKGROUND_1}${BOLD_TEXT}${model_part}${NORMAL_TEXT}${RESPONSE_BACKGROUND_1}${RESPONSE_FOREGROUND_1}${rest_of_line}${RESET}"
      prev_bg_toggle=1
    else
      display_text="${RESPONSE_BACKGROUND_2}${BOLD_TEXT}${model_part}${NORMAL_TEXT}${RESPONSE_BACKGROUND_2}${RESPONSE_FOREGROUND_2}${rest_of_line}${RESET}"
      prev_bg_toggle=0
    fi
    echo -e "$display_text"
  else
    # No model part to bold, just apply colors
    if [ $prev_bg_toggle -eq 0 ]; then
      echo -e "${RESPONSE_BACKGROUND_1}${RESPONSE_FOREGROUND_1}${formatted}${RESET}"
      prev_bg_toggle=1
    else
      echo -e "${RESPONSE_BACKGROUND_2}${RESPONSE_FOREGROUND_2}${formatted}${RESET}"
      prev_bg_toggle=0
    fi
  fi
}

runCommandWithTimeout() {
  ollama run "${model}" --hidethinking -- "${chatInstructions}${context}" 2>/dev/null &
  pid=$!
  (
    sleep "$TIMEOUT"
    debug "[ERROR: Session Timeout after ${TIMEOUT} seconds]"
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
  changeNotice="*** $model left the chat"
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
    echo; echo "[SYSTEM] No models remaining. Chat ending."
    exit 0
  fi
}

setNewTopic() {
  changeNotice="*** $model changed topic to: $1"
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
  debug "startRound: <$(printf '%s> <' "${round[@]}" | sed 's/> <$//')"
}

export OLLAMA_MAX_LOADED_MODELS=1
parseCommandLine "$@"
echo; echo "$NAME v$VERSION"; echo;
setModels
startRound
echo "[SYSTEM] ${#models[@]} models in chat: $(roundList)";
echo "[SYSTEM] TIMEOUT: ${TIMEOUT} seconds"; echo
setTopic
context=""
addToContext "*** Topic: $topic"
while true; do
  model="${round[0]}" # Get first speaker from round
  debug "model: $model"
  round=("${round[@]:1}") # Remove speaker from round
  if [ ${#round[@]} -eq 0 ]; then # If everyone has spoken, then restart round
    startRound
  fi
  debug "round: <$(printf '%s> <' "${round[@]}" | sed 's/> <$//')>"
  setInstructions
  response=$(runCommandWithTimeout)
  if [ -z "${response}" ]; then
    response="" # "[ERROR: No response from ${model}]"
  fi
  handleCommands && addToContext "<$model> $response"
done
