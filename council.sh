#!/bin/bash

NAME="llm-council"
VERSION="0.8"
URL="https://github.com/attogram/llm-council"
CONTEXT_SIZE="250" # number of lines in the context
TIMEOUT="30" # number of seconds to wait for model response

echo; echo "$NAME v$VERSION";

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

function setInstructions {
  chatInstructions="You are in a group chat room.
You are user <$model>.  Do not pretend to be anyone else.  Answer only as yourself.
Be concise in your response.  You have only ${TIMEOUT} seconds to complete your response.
The users in the room: $(modelsList)
To mention other users, use syntax: '@username'. Do not use syntax '<username>'.
Work together with the other users.  See the latest chat log below for context.
You do not have to agree with the other users, use your best judgment to form your own opinions.
To change the room topic, send ONLY the command: '/topic The New Topic'
This room is a council. The council is tasked with these instructions:
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

function updateContext {
  context+="

<$model> $response"
  context=$(echo "$context" | tail -n "$CONTEXT_SIZE") # get most recent $CONTEXT_SIZE lines of chat log
  saveContext
}

function saveContext {
  echo "$context" > "./context.txt" # save current context to file
}

function runCommandWithTimeout {
  local command="$1"
  local timeout="$2"
  $command 2>/dev/null &
  pid=$!
  (
    sleep $timeout
    echo; echo "[ERROR: Session Timeout after ${timeout} seconds]"
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

function checkForTopicCommand {
  local modelResponse="$1"
  # Remove leading/trailing whitespace and check if it matches /topic pattern
  local trimmedResponse=$(echo "$modelResponse" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ "$trimmedResponse" =~ ^/topic[[:space:]]+(.+)$ ]]; then
    local newTopic="${BASH_REMATCH[1]}"
    setNewTopic "$newTopic"
  fi
}

function setNewTopic {
  local newTopic="$1"
  echo; echo "[SYSTEM] Topic changed to: $newTopic"
  prompt="$newTopic"
  setInstructions
  context+="

/topic $newTopic
"
  saveContext
}

export OLLAMA_MAX_LOADED_MODELS=1

parseCommandLine "$@"
setModels
echo; echo "Users in chat: $(modelsList)"
setPrompt
model=$(getRandomModel)
setInstructions
context="/topic $prompt"
saveContext
echo; echo "${context}"

while true; do
  echo
  response=$(runCommandWithTimeout "ollama run ${model} --hidethinking -- ${chatInstructions}${context}" "$TIMEOUT")
  if [ -z "${response}" ]; then
    response="<$model> [ERROR: No response from ${model}]"
  fi
  echo "<$model> $response"
  updateContext
  checkForTopicCommand "$response"
  model=$(getRandomModel "$model")
  setInstructions
done
