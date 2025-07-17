#!/usr/bin/env bash
#
# LLM Council
# Start a chat room between all, or some, of your models running on Ollama.
#
# Usage help: ./council.sh -h

NAME="llm-council"
VERSION="3.0"
URL="https://github.com/attogram/llm-council"

trap exitCleanup INT SIGINT

CHAT_LOG_LINES=500 # number of lines in the chat log
LOG_DIRECTORY="./logs" # Log Directory (no slash at end)
DEBUG_MODE=0 # Debug mode. 1 = debug on, 2 = debug off
TIMEOUT=20 # number of seconds to wait for model response
TEXT_WRAP=0 # Text wrap. 0 = no wrap, >0 = wrap line
TIME_STAMP=0 # Time Stamps for every message. 0 = no, 1 = yes
MESSAGE_LIMIT=200 # Word limit for messages, suggested to models in the Chat Instructions
CHAT_MODE="nouser" # Chat mode: nouser, reply

banner() {
  echo "
▗▖   ▗▖   ▗▖  ▗▖     ▗▄▄▖ ▗▄▖ ▗▖ ▗▖▗▖  ▗▖ ▗▄▄▖▗▄▄▄▖▗▖
▐▌   ▐▌   ▐▛▚▞▜▌    ▐▌   ▐▌ ▐▌▐▌ ▐▌▐▛▚▖▐▌▐▌     █  ▐▌
▐▙▄▄▖▐▙▄▄▖▐▌  ▐▌    ▝▚▄▄▖▝▚▄▞▘▝▚▄▞▘▐▌ ▝▜▌▝▚▄▄▖▗▄█▄▖▐▙▄▄▖
"
}

usage() {
  me=$(basename "$0")
  echo "$NAME"; echo
  echo "Usage:"
  echo "  ./$me [flags]"
  echo "  ./$me [flags] [topic]"
  echo; echo "Flags:";
  echo "  -m model1,model2  Use specific models (comma separated list)"
  echo "  -r,  -reply       User may respond after every model message"
  echo "  -nu, -nouser      No user in chat, only models (Default)"
  echo "  -to, -timeout     Set timeout to # seconds"
  echo "  -ts, -timestamp   Show Date and time for every message"
  echo "  -w,  -wrap        Text wrap lines to # characters"
  echo "  -nc, -nocolors    Do not use ANSI colors"
  echo "  -d,  -debug       Debug Mode"
  echo "  -v,  -version     Show version information"
  echo "  -h,  -help        Help for $NAME"
  echo '  [topic]           Set the chat room topic (Optional)'
}

debug() {
  if [ "$DEBUG_MODE" -eq 1 ]; then
    >&2 echo -e "${COLOR_DEBUG}[$(date '+%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
  fi
}

setInstructions() {
  chatInstructions="You are in a group chat with ${#models[@]} members.
You are user <$model>.
If you want to mention another user, you MUST use syntax: @username.
If you want to leave the chat, send ONLY the 1 line command: /quit <optional reason>
If you want to set a new topic, send ONLY the 1 line command: /topic <new topic>
Review the Chat Log below. Then send your message to the group chat.
Be concise. You MUST limit your response to $MESSAGE_LIMIT words or less.

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
      -nu|-nouser|--nouser) # Chat mode: no user
        CHAT_MODE="nouser"
        shift
        ;;
      -r|-reply|--reply) # Chat mode: user reply after every model message
        CHAT_MODE="reply"
        shift
        ;;
      -nc|-nocolor|--nocolor|-nocolors|--nocolors) # No ANSI Colors
        noColors
        shift
        ;;
      -m|-model|--model|-models|--models) # specify models to run
        validateAndSetArgument "$1" "$2" "modelsList"
        shift 2
        ;;
      -to|-timeout|--timeout) # set timeout
        validateAndSetArgument "$1" "$2" "TIMEOUT"
        shift 2
        ;;
      -ts|-timestamp|--timestamp|-timestamps|--timestamps) # show timestamps
        TIME_STAMP=1
        shift
        ;;
      -v|-version|--version) # version
        echo "$NAME v$VERSION"
        exit 0
        ;;
      -w|-wrap|--wrap) # wrap lines
        validateAndSetArgument "$1" "$2" "TEXT_WRAP"
        shift 2
        ;;
      -*|--*=|--*) # unsupported flags
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
  if [ -n "$topic" ]; then # if topic was already set from command line
    return
  fi
  if [ -t 0 ]; then # Check if input is from a terminal (interactive)
    echo -n "${COLOR_SYSTEM}/topic ${COLOR_RESET} "
    read -r topic # Read topic from user input
    echo -ne "\033[A\r\033[K" # move 1 line up and clear line
    return
  fi
  topic=$(cat) # Read from standard input (pipe or file)
}

sendMessageToTerminal() {
  if [ "$TEXT_WRAP" -ge 1 ]; then
    echo -e "$1" | fold -s -w "$TEXT_WRAP"
  else
    echo -e "$1"
  fi
}

displayContextAdded() {
  local message="$1"
  local display=""
  local name=""
  local content=""
  local timestamp=""
  if [[ "$message" =~ ^'<'[^'>']+'>' ]] ; then
    name=${BASH_REMATCH[0]} # <name>
    content=${message#$name} # remove the <name> from content
  fi
  if [[ "$message" =~ ^(\[[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\])\ ('<'[^'>']+'>')\ *(.*) ]]; then
    timestamp=${BASH_REMATCH[1]} # [YYYY-MM-DD HH:MM:SS]
    timestamp+=" "
    name=${BASH_REMATCH[2]} # <name>
    name+=" "
    content=${BASH_REMATCH[3]} # actual content after timestamp and name
  fi
  if [ -n "$name" ]; then
    # Apply bold formatting to <name> at start of line, toggle color scheme
    if [ $response_toggle -eq 0 ]; then
      display="${timestamp}${COLOR_RESPONSE_1}${TEXT_BOLD}${name}${TEXT_NORMAL}${COLOR_RESPONSE_1}${content}${COLOR_RESET}"
      response_toggle=1
    else
      display="${timestamp}${COLOR_RESPONSE_2}${TEXT_BOLD}${name}${TEXT_NORMAL}${COLOR_RESPONSE_2}${content}${COLOR_RESET}"
      response_toggle=0
    fi
  else
    # Not a user/model message, is a system message
    display="${COLOR_SYSTEM}${message}${COLOR_RESET}"
  fi
  sendMessageToTerminal "$display"
}

showTimestamp() {
  if [ "$TIME_STAMP" -eq 1 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] "
  fi
}

setupLogging() {
   if [ ! -d "$LOG_DIRECTORY" ]; then # if log directory doesn't exist
       mkdir "$LOG_DIRECTORY" # create it # 2>/dev/null
   fi
   echo -e "\nChat Log Started: $(date '+%Y-%m-%d %H:%M:%S')\n" >> "${LOG_DIRECTORY}/messages.txt"
}

saveInstructionsToLog() {
  echo -e "$chatInstructions" > "${LOG_DIRECTORY}/instructions.txt"
}

saveMessageToLog() {
  echo -e "$1" >> "${LOG_DIRECTORY}/messages.txt" # append message to message log
}

addToContext() {
  local message="$1"
  #debug "addToContext: start: [$message]"
  message="$(showTimestamp)${message}" # optional timestamp
  #debug "addToContext: times: [$message]"
  if [ "$TEXT_WRAP" -ge 1 ]; then
    message=$(echo -e "$message" | fold -s -w "$TEXT_WRAP")
    #debug "addToContext: wrap: [$message]"
  fi
  #debug "addToContext: append context: [$message]"
  context+="\n$message" # add the message to the context
  #debug "addToContext: trim context: $CHAT_LOG_LINES lines"
  context=$(echo "$context" | tail -n "$CHAT_LOG_LINES") # trim context to $CHAT_LOG_LINES lines
  #debug "addToContext: saveMessageToLog: [$message]"
  saveMessageToLog "$message"
  #debug "addToContext: displayContextAdded: [$message]"
  displayContextAdded "$message"
  #debug "addToContext: end"
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
  #debug "runCommandWithTimeout: start"
  (
    #debug "runCommandWithTimeout: ollama run: start"
    ollama run "${model}" --hidethinking -- "${chatInstructions}${context}" 2>/dev/null
    #debug "runCommandWithTimeout: ollama run: end"
  ) &
  pidOllama=$!
  #debug "runCommandWithTimeout: pidOllama=$pidOllama"

  (
    #debug "runCommandWithTimeout: ollama timeout watch: start: TIMEOUT=$TIMEOUT"
    sleep "$TIMEOUT"
    #debug "runCommandWithTimeout: ollama timeout watch: sleep $TIMEOUT done"
    if kill -0 $pidOllama 2>/dev/null; then
      #debug "runCommandWithTimeout: ollama timeout watch: kill $pidOllama pidOllama"
      kill $pidOllama 2>/dev/null
    fi
    #debug "runCommandWithTimeout: ollama timeout watch: end"
  ) &
  pidOllamaTimeout=$!
  #debug "runCommandWithTimeout: pidOllamaTimeout=$pidOllamaTimeout"

  #debug "runCommandWithTimeout: start: wait $pidOllama pidOllama"
  wait $pidOllama 2>/dev/null
  #debug "runCommandWithTimeout: end: wait $pidOllama pidOllama"
  #debug "runCommandWithTimeout: ps: $(ps)"

  #debug "runCommandWithTimeout: kill $pidOllamaTimeout pidOllamaTimeout"
  kill $pidOllamaTimeout 2>/dev/null

  #debug "runCommandWithTimeout: ps: $(ps)"
  #debug "runCommandWithTimeout: end"
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

handleCommands() {
  local response="$1"
  # Remove leading/trailing whitespace
  local trimmedResponse=$(echo "$response" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  # check if it matches /topic pattern
  if [[ "$trimmedResponse" =~ ^/topic[[:space:]]+(.+)$ ]]; then
    addToContext "*** <$model> changed topic to: ${BASH_REMATCH[1]}"
    return 1;
  # To leave the chat room, send ONLY the command: /quit <optional reason>
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

stopModel() {
  ollama stop "$1"
  debug "$(ollama ps)"
  debug "Stopped model: $1"
}

userReply() {
  if [[ "$CHAT_MODE" != "reply" ]]; then
    return
  fi
  model="user"
  local userMessage=""
  echo -n "${COLOR_SYSTEM}<$model>${COLOR_RESET} "
  read -r userMessage < /dev/tty
  echo -ne "\033[A\r\033[K" # move 1 line up and clear line
  if [ -n "$userMessage" ]; then
    handleCommands "$userMessage" && addToContext "<$model> $userMessage"
  else
    debug "No user message"
  fi
}

intro() {
  sendMessageToTerminal "${COLOR_SYSTEM}\n$(banner)\n$NAME v$VERSION\n"
  allParticipants="$(printf "<%s> " "${models[@]}")"
  allParticipantsCount="${#models[@]}"
  if [[ "$CHAT_MODE" == "reply" ]]; then
    allParticipants="<user> $allParticipants"
    ((allParticipantsCount++))
  fi
  sendMessageToTerminal "$allParticipantsCount entities invited to the chat room:"
  sendMessageToTerminal "$allParticipants"
  sendMessageToTerminal "${COLOR_RESET}"
  debug "CHAT_MODE: ${CHAT_MODE}"
  debug "TIMEOUT: ${TIMEOUT} seconds"
  debug "CHAT_LOG_LINES: ${CHAT_LOG_LINES}"
  debug "TEXT_WRAP: ${TEXT_WRAP}"
  debug "MESSAGE_LIMIT: ${MESSAGE_LIMIT}"
}

allJoinTheChat() {
  if [[ "$CHAT_MODE" == "reply" ]]; then
    addToContext "*** <user> has joined the chat as administrator"
  fi
  for joiningModel in "${models[@]}"; do
    addToContext "*** <$joiningModel> has joined the chat"
  done
}

function exitCleanup() {
  debug "exitCleanup"
  echo
  addToContext "*** <user> has closed the chat"
  echo -ne "$COLOR_RESET"
  stty sane 2>/dev/null
  echo
  exit 0
}

export OLLAMA_MAX_LOADED_MODELS=1
yesColors
parseCommandLine "$@"
setModels
setupLogging
intro
setTopic
allJoinTheChat
context=""
if [ -n "$topic" ]; then # If /topic wasn't set on the command line
  addToContext "*** <user> changed topic to: $topic"
fi
setInstructions; saveInstructionsToLog
userReply # In Reply mode, user gets to send the first message
startRound
while true; do
  model="${round[0]}" # Get first speaker from round
  round=("${round[@]:1}") # Remove speaker from round
  if [ ${#round[@]} -eq 0 ]; then startRound; fi # If everyone has spoken, then restart round
  debug "model: <$model> -- round: <$(printf '%s> <' "${round[@]}" | sed 's/> <$//')>"
  setInstructions
  debug "calling: runCommandWithTimeout"
  echo -n "${COLOR_SYSTEM}*** <$model> is typing...${COLOR_RESET}"
  response=$(runCommandWithTimeout)
  echo -ne "\r\033[K" # clear line
  debug "called: runCommandWithTimeout"
  response=$(removeThinking "$response")
  stopModel "$model"
  if [ -z "${response}" ]; then
    debug "[ERROR] No response from <${model}> within $TIMEOUT seconds"
  else
    handleCommands "$response" && addToContext "<$model> $response"
    userReply # In reply mode, user gets to respond after every model message
  fi
done
exitCleanup
