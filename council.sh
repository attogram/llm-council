#!/bin/bash

NAME="llm-council"
VERSION="0.1"
URL="https://github.com/attogram/llm-council"

# echo; echo "$NAME v$VERSION"; echo

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
  eval set -- "$prompt"
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
    echo "Enter prompt:";
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

function getDateTime {
  echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

export OLLAMA_MAX_LOADED_MODELS=2
parseCommandLine "$@"
setModels
setPrompt

chatInstructions="You are chatting.
Included below is a log of the conversation so far, in reverse chronological order.
Continue the conversation:"

context="<user> wrote @ $(getDateTime):
$prompt"

echo "$context" > "./context.txt" # save current context to file

echo
echo "$context"
echo

model=$(getRandomModel)

while true; do
  echo -n "<$model>"
  response=$(ollama run "$model" --hidethinking -- "$chatInstructions \n $context" 2> /dev/null)

  if [ -z "${response}" ]; then
    response="?"
  fi
  wroteAt="wrote @ $(getDateTime):"

  echo " $wroteAt
$response"
  echo

  context="<$model> $wroteAt
$response

$context"

  context=$(echo "$context" | head -n 500)  # trim to first 100 lines

  echo "$context" > "./context.txt" # save current context to file

  model=$(getRandomModel "$model")
done
