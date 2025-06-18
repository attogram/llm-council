#!/bin/bash
#
# llm-council
#
# A group chat room with all your ollama models, or a selection of your ollama models
#
# Usage:
#
#  Use all models:
#    ./council.sh
#
#  Specify which models to use:
#    ./council.sh -m model1,model2,model3
#
#  Set Timeout
#    ./council.sh -t 30
#
#
NAME="llm-council"
VERSION="1.3"
URL="https://github.com/attogram/llm-council"
CONTEXT_SIZE="250" # number of lines in the context
TIMEOUT="60" # number of seconds to wait for model response

echo; echo "$NAME v$VERSION";

function setInstructions {
  chatInstructions="You are in a group chat room.
You are user <$model>. Answer only as yourself. Do not pretend to be anyone else.
Be concise in your response. You have only ${TIMEOUT} seconds to complete your response.
To mention other users, use syntax: '@username'.
You do not have to agree with the other users, use your best judgment to form your own opinions.
You may steer the conversation to a new topic. Send ONLY the command: /topic <new topic>
You may leave the chat room if you want to end your participation. Send ONLY the command: /quit <optional reason>
See the chat log below for context.
The current room topic is:
---
$prompt
---

Chat Log:
"
  saveInstructions
}

function saveInstructions {
  echo "$chatInstructions" > "./instructions.txt" # save current context to file
}

function parseCommandLine {
  modelsList=""
  resultsDirectory="results"
  prompt=""
  while (( "$#" )); do
    case "$1" in
      -m) # specify models to run
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
          modelsList=$2
          shift 2
        else
          echo "Error: Argument for $1 is missing" >&2
          exit 1
        fi
        ;;
      -t) # set timeout
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
          TIMEOUT=$2
          shift 2
        else
          echo "Error: Argument for $1 is missing" >&2
          exit 1
        fi
        ;;
      -*|--*=) # unsupported flags
        echo "Error: unsupported argument: $1" >&2
        exit 1
        ;;
      *) # preserve positional arguments
        prompt+="$1"
        shift
        ;;
    esac
  done
  # set positional arguments in their proper place
  eval set -- "${prompt}"
}

function setModels {
  models=($(ollama list | awk '{if (NR > 1) print $1}' | sort)) # Get list of models, sorted alphabetically
  if [ -z "$models" ]; then
    echo "No models found. Please install models with 'ollama pull <model-name>'" >&2
    exit 1
  fi

  parsedModels=()
  if [ -n "$modelsList" ]; then
    IFS=',' read -ra modelsListArray <<< "$modelsList" # parse csv into modelsListArray
    for m in "${modelsListArray[@]}"; do
      if [[ "${models[*]}" =~ "$m" ]]; then # if model exists
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
  
  if [ ${#models[@]} -lt 2 ]; then
    echo "Error: there must be at least 2 models to chat with each other" >&2
    exit 1
  fi
  
}

function setPrompt {
  if [ -n "$prompt" ]; then # if prompt is already set from command line
    return
  fi

  if [ -t 0 ]; then # Check if input is from a terminal (interactive)
    echo; echo "Enter prompt:";
    read -r prompt # Read prompt from user input
    return
  fi

  prompt=$(cat) # Read from standard input (pipe or file)
}

function getRandomModel {
  local exclude_model=$1
  if [ -z "$exclude_model" ]; then
    echo "${models[$RANDOM % ${#models[@]}]}"
    return
  fi
  local filtered_models=()
  for model in "${models[@]}"; do
    if [ "$model" != "$exclude_model" ]; then
      filtered_models+=("$model")
    fi
  done
  echo "${filtered_models[$RANDOM % ${#filtered_models[@]}]}"
}

function addToContext {
  context+="

$1"
  echo; echo "$1"
  context=$(echo "$context" | tail -n "$CONTEXT_SIZE") # get most recent $CONTEXT_SIZE lines of chat log
  saveContext
}

function saveContext {
  echo "$context" > "./context.txt" # save current context to file
}

function runCommandWithTimeout {
  local command="$1"
  $command 2>/dev/null &
  pid=$!
  (
    sleep "$TIMEOUT"
    echo; echo "[ERROR: Session Timeout after ${TIMEOUT} seconds]"
    if kill -0 $pid 2>/dev/null; then
      kill $pid 2>/dev/null
    fi
  ) &
  wait_pid=$!
  wait $pid 2>/dev/null
  kill $wait_pid 2>/dev/null
}

function modelsList {
  printf "<%s> " "${models[@]}"
}

function quitChat {
  local model="$1"
  local reason="$2"
  changeNotice="[SYSTEM] <$model> has left the chat"
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

  #echo; echo "[DEBUG] ${#models[@]} users in chat: $(modelsList)"

  # Check if we still have enough models to continue
  if [ ${#models[@]} -lt 1 ]; then
    echo; echo "[SYSTEM] No models remaining. Chat ending."
    exit 0
  fi
}

function setNewTopic {
  changeNotice="[SYSTEM] <$model> changed the topic to: $1"
  prompt="$1"
  setInstructions
  addToContext "$changeNotice"
}

function handleCommands {
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

export OLLAMA_MAX_LOADED_MODELS=1

parseCommandLine "$@"
setModels
echo; echo "[DEBUG] ${#models[@]} users in chat: $(modelsList)"
echo; echo "[DEBUG] TIMEOUT: ${TIMEOUT} seconds"
setPrompt
model=$(getRandomModel)
context="[SYSTEM] Topic is: $prompt"
echo; echo "$context"; echo;


while true; do
  response=$(runCommandWithTimeout "ollama run ${model} --hidethinking -- ${chatInstructions}${context}")
  if [ -z "${response}" ]; then
    response="[ERROR: No response from ${model}]"
  fi
  handleCommands && addToContext "<$model> $response"
  model=$(getRandomModel "$model")
  setInstructions
done
