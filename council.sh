#!/usr/bin/env bash
#
# LLM Council
# Start a chat room between all, or some, of your models running on Ollama.
#
# Usage help: ./council.sh -h

NAME="llm-council"
VERSION="3.16.1"
URL="https://github.com/attogram/llm-council"

trap exitCleanup SIGINT # Trap CONTROL-C to cleanly exit

context=""    # The Chat Log
model=""      # The current active model
models=()     # List of models currently in chat
round=()      # List of models in the current round
modelsList="" # User specified models list
topic=""      # The current topic
rules=""      # Chat Rules sent in the prompt to models
noModels=0    # Start with No models (0 = no, 1 = yes)
colorToggle=0 # Track alternating response color schemes

CHAT_MODE="reply"  # Chat mode: nouser, reply
CHAT_LOG_LINES=500 # number of lines in the chat log
LOG_DIR="./logs"   # Log Directory (no slash at end)
DEBUG_MODE=0       # Debug mode. 1 = debug on, 2 = debug off
TIMEOUT=20         # Seconds to wait for model response
TEXT_WRAP=0        # Text wrap. 0 = no wrap, >0 = wrap line
TIME_STAMP=0       # Time Stamps for every message. 0 = no, 1 = yes
MESSAGE_LIMIT=200  # Word limit for messages, suggested to models in the Chat Rules
SHOW_EMPTY=0       # Show Empty Messages. 0 = no, 1 = yes

RETURN_SUCCESS=0
RETURN_ERROR=1
YES_COMMAND_HANDLED=1
NO_COMMAND_HANDLED=0

banner() {
  echo "
▗▖   ▗▖   ▗▖  ▗▖     ▗▄▄▖ ▗▄▖ ▗▖ ▗▖▗▖  ▗▖ ▗▄▄▖▗▄▄▄▖▗▖
▐▌   ▐▌   ▐▛▚▞▜▌    ▐▌   ▐▌ ▐▌▐▌ ▐▌▐▛▚▖▐▌▐▌     █  ▐▌
▐▙▄▄▖▐▙▄▄▖▐▌  ▐▌    ▝▚▄▄▖▝▚▄▞▘▝▚▄▞▘▐▌ ▝▜▌▝▚▄▄▖▗▄█▄▖▐▙▄▄▖
"
}

usage() {
  me=$(basename "$0")
  echo "
$NAME v$VERSION

Usage:
  ./$me [flags]
  ./$me [flags] [topic]

Flags:
  -m,  -models      Specify which models join the chat (comma separated list)
  -nm, -nomodels    Start chat with no models
  -r,  -reply       User may respond after every model message (Default)
  -nu, -nouser      No user in chat, only models
  -to, -timeout     Set timeout to # seconds
  -ts, -timestamp   Show Date and time for every message
  -se, -showempty   Show Empty messages (from timeouts)
  -w,  -wrap        Text wrap lines to # characters
  -nc, -nocolors    Do not use ANSI colors
  -d,  -debug       Debug Mode
  -v,  -version     Show version information
  -h,  -help        Help for $NAME
  [topic]           Set the chat topic (Optional)
"
}

commandHelp() {
  echo "Chat Commands:

/topic [Your Topic]      - Set a new topic
/quit (optional reason)  - Leave the chat

Admin Commands:

/stop            - Close the chat and exit
/count           - Show number of models in chat
/list            - List models in chat
/olist           - Show available models in Ollama
/ps              - Show running models in Ollama
/kick [model]    - Kick model out of the chat
/invite [model]  - Invite model into the chat
/rules           - View the Chat Rules sent to models
/log             - View the Chat Log
/round           - List models in the current round
/clear           - Clear the screen
/help            - This command list
"
}

setRules() {
  rules="You are in a group chat with ${#models[@]} members.
You are user <${model:-user}>.
If you want to mention another user, you MUST use syntax: @username.
If you want to leave the chat, send ONLY the 1 line command: /quit <optional reason>
If you want to set a new topic, send ONLY the 1 line command: /topic <new topic>
Review the Chat Log below. Then send your message to the group chat.
Be concise. You MUST limit your response to $MESSAGE_LIMIT words or less.

Chat Log:
"
}

yesColors() {
  COLOR_RESPONSE_1=$'\e[37m\e[48;5;233m' # white text, dark grey background
  COLOR_RESPONSE_2=$'\e[37m\e[40m'  # white text, black background
  COLOR_SYSTEM=$'\e[37m\e[48;5;17m' # white text, dark blue background
  COLOR_DEBUG=$'\e[30m\e[43m'       # black text, yellow background
  TEXT_NORMAL=$'\e[22m'             # Normal style text
  TEXT_BOLD=$'\e[1m'                # Bold style text
  COLOR_RESET=$'\e[0m'              # Reset terminal colors
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

debug() {
  if [ "$DEBUG_MODE" -eq 1 ]; then
    >&2 echo -e "${COLOR_DEBUG}[$(date '+%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
  fi
}

sendToTerminal() {
  if [ "$TEXT_WRAP" -ge 1 ]; then
    echo -e "$1" | fold -s -w "$TEXT_WRAP"
  else
    echo -e "$1"
  fi
}

notice() {
  >&2 sendToTerminal "${COLOR_DEBUG}NOTICE: $1${COLOR_RESET}"
}

error() {
  >&2 sendToTerminal "${COLOR_DEBUG}ERROR: $1${COLOR_RESET}"
}

validateAndSetArgument() {
  local flag=$1
  local value=$2
  local var_name=$3
  if [ -n "$value" ] && [ ${value:0:1} != "-" ]; then
    eval "$var_name='$value'"
    return $RETURN_SUCCESS
  else
    error "Argument for $flag is missing" >&2
    exit $RETURN_ERROR
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
        exit $RETURN_SUCCESS
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
      -nm|-nomodels|--nomodels)
        noModels=1
        shift
        ;;
      -se|-showempty|--showempty|-empty|--empty) # Show empty messages
        SHOW_EMPTY=1
        shift
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
        exit $RETURN_SUCCESS
        ;;
      -w|-wrap|--wrap) # wrap lines
        validateAndSetArgument "$1" "$2" "TEXT_WRAP"
        shift 2
        ;;
      -*) # unsupported flags
        error "Unsupported flag: $1" >&2
        exit $RETURN_ERROR
        ;;
      *) # preserve positional arguments
        topic+="$1"
        shift
        ;;
    esac
  done
  # set positional arguments in their proper place
  eval set -- "$topic"
}

setModels() {
  if [ "$noModels" -eq 1 ]; then
    return
  fi
  models=($(ollama list | awk '{if (NR > 1) print $1}' | sort)) # Get list of models, sorted alphabetically
  if [ -z "$models" ]; then
    error "No models installed in Ollama. Please install models with 'ollama pull <model-name>'" >&2
    exit $RETURN_ERROR
  fi
  local parsedModels=()
  if [ -n "$modelsList" ]; then # If user supplied a model list with -m
    IFS=',' read -ra modelsListArray <<< "$modelsList" # parse csv into modelsListArray
    for m in "${modelsListArray[@]}"; do
      if [[ " ${models[*]} " =~ " $m " ]]; then # if model exists
        parsedModels+=("$m")
      else
        error "Model not found: $m" >&2
        exit $RETURN_ERROR
      fi
    done
  fi
  if [ -n "$parsedModels" ]; then
    IFS=$'\n' sortedParsedModels=($(sort <<<"${parsedModels[*]}"))
    unset IFS
    models=("${sortedParsedModels[@]}")
  fi
  if [ ${#models[@]} -lt 1 ]; then
    notice "No models in the chat" >&2
    return #exit $RETURN_ERROR
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
    if [ $colorToggle -eq 0 ]; then
      display="$timestamp${COLOR_RESPONSE_1}${TEXT_BOLD}$name${TEXT_NORMAL}${COLOR_RESPONSE_1}$content${COLOR_RESET}"
      colorToggle=1
    else
      display="$timestamp${COLOR_RESPONSE_2}${TEXT_BOLD}$name${TEXT_NORMAL}${COLOR_RESPONSE_2}$content${COLOR_RESET}"
      colorToggle=0
    fi
  else
    display="${COLOR_SYSTEM}$message${COLOR_RESET}" # System message (Not a user or model message)
  fi
  sendToTerminal "$display"
}

showTimestamp() {
  if [ "$TIME_STAMP" -eq 1 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] "
  fi
}

setupLogging() {
   if [ ! -d "$LOG_DIR" ]; then # if log directory doesn't exist
       mkdir "$LOG_DIR" # create it # 2>/dev/null
   fi
   echo -e "\nChat Log Started: $(date '+%Y-%m-%d %H:%M:%S')\n" >> "${LOG_DIR}/messages.txt"
}

saveRulesToLog() {
  echo -e "$rules" > "${LOG_DIR}/rules.txt"
}

saveMessageToLog() {
  echo -e "$1" >> "${LOG_DIR}/messages.txt" # append message to message log
}

addToContext() {
  local message="$1"
  message="$(showTimestamp)${message}" # optional timestamp
  if [ "$TEXT_WRAP" -ge 1 ]; then
    message=$(echo -e "$message" | fold -s -w "$TEXT_WRAP")
  fi
  context+="\n$message" # add the message to the context
  context=$(echo "$context" | tail -n "$CHAT_LOG_LINES") # trim context to $CHAT_LOG_LINES lines
  saveMessageToLog "$message"
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

ollamaRunWithTimeout() {
  (
    ollama run "$model" --hidethinking -- "${rules}${context}" 2>/dev/null
  ) &
  local pidOllama=$!
  (
    sleep "$TIMEOUT"
    if kill -0 $pidOllama 2>/dev/null; then
      kill $pidOllama 2>/dev/null
    fi
  ) &
  local pidOllamaTimeout=$!
  wait $pidOllama 2>/dev/null
  kill $pidOllamaTimeout 2>/dev/null
}

removeModel() {
  local modelToRemove="$1"
  local newModels=()
  for m in "${models[@]}"; do
    if [ " $m " != " $modelToRemove " ]; then
      newModels+=("$m")
    fi
  done
  models=("${newModels[@]}")
}

exitCleanup() {
  debug "exitCleanup"
  echo
  addToContext "*** The chat is now closed"
  echo -ne "$COLOR_RESET"
  stty sane 2>/dev/null
  echo
  exit $RETURN_SUCCESS
}

quitChat() {
  local model="$1"
  local reason="$2"
  changeNotice="*** <$model> left the chat"
  if [ -n "$reason" ]; then
    changeNotice+=": $reason"
  fi
  addToContext "$changeNotice"
  if [ "$model" == "user" ]; then # if <user> quits, change CHAT_MODE
    CHAT_MODE="nouser"
    if [ -z "$models" ]; then # no models in chat
      exitCleanup # end the chat
    fi
    return
  fi
  removeModel "$model"
  if [ ${#models[@]} -lt 1 ]; then
    # TODO - if user is in chat, do not end
    echo; echo "${COLOR_SYSTEM}*** No models remaining. Chat ending.${COLOR_RESET}"
    exit $RETURN_SUCCESS
  fi
}

handleAdminCommands() {
  local command="$1"
  local message="$2"
  case "$command" in
    /help) # Command help
      sendToTerminal "\n$(commandHelp)\n"
      return $YES_COMMAND_HANDLED
      ;;
    /exit|/stop|/end|/close|/bye) # End the chat
      exitCleanup
      ;;
    /count) # Count of models currently in chat
      sendToTerminal "\nThere are ${#models[@]} models in the chat.\n"
      return $YES_COMMAND_HANDLED
      ;;
    /list) # List models currently in chat
      sendToTerminal "\nThere are ${#models[@]} models in the chat:\n"
      sendToTerminal "$(printf "%s\n" "${models[@]}")\n"
      return $YES_COMMAND_HANDLED
      ;;
    /olist) # Ollama list
      sendToTerminal "\nModels available in Ollama:\n"
      ollama list | awk '{if (NR > 1) print $1}' | sort
      return $YES_COMMAND_HANDLED
      ;;
    /ps) # Ollama ps
      sendToTerminal "\n"
      ollama ps
      sendToTerminal "\n"
      return $YES_COMMAND_HANDLED
      ;;
    /kick) # Kick a model out of the chat
      if [ -z "$message" ]; then
        error "No model specified to kick"
        return $YES_COMMAND_HANDLED
      fi
      # TODO - check if model is in the chat
      addToContext "*** <user> kicked <$message> out of the chat"
      removeModel "$message"
      return $YES_COMMAND_HANDLED
      ;;
    /invite) # Invite a model to join the chat
      if [ -z "$message" ]; then
        error "No model specified to invite"
        return $YES_COMMAND_HANDLED
      fi
      # TODO - check if model exists in Ollama...
      # TODO - check if model is already present in chat...
      #addToContext "*** <user> invited <$response> to the chat"
      models+=("$message")
      round+=("$message")
      addToContext "*** <$message> joined the chat"
      return $YES_COMMAND_HANDLED
      ;;
    /rules|/rule|/instruction|/instructions) # Show the Chat Rules
      sendToTerminal "\n$rules"
      return $YES_COMMAND_HANDLED
      ;;
    /log|/logs|/messages|/msgs|/context) # Show the Chat Log
      sendToTerminal "\n$context\n"
      return $YES_COMMAND_HANDLED
      ;;
    /round) # Show current round
      sendToTerminal "\nCurrent Round:\n"
      sendToTerminal "$(printf "%s\n" "${round[@]}")\n"
      return $YES_COMMAND_HANDLED
      ;;
    /clear|/cls) # clear the screen
      clear
      return $YES_COMMAND_HANDLED
      ;;
    /*)
      error "Unknown Command"
      return $YES_COMMAND_HANDLED
      ;;
  esac
  return $NO_COMMAND_HANDLED
}

handleBasicCommands() {
  local command="$1"
  local message="$2"
  case "$command" in
    /topic) # Change the topic
      if [ -z "$message" ]; then
        # TODO - differentiate between user /topic (show error) and model /topic
        error "No topic to set"
        return $YES_COMMAND_HANDLED
      fi
      topic="$message"
      addToContext "*** <$model> changed topic to: $message"
      return $YES_COMMAND_HANDLED
      ;;
    /quit|/leave)
      quitChat "$model" "$message"
      return $YES_COMMAND_HANDLED
      ;;
  esac
  return $NO_COMMAND_HANDLED
}

handleCommands() {
  local message="$1"
  message=$(echo "$message" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') # Remove leading/trailing whitespace
  local command=$(echo "$message" | awk '{print $1}' | tr '[:upper:]' '[:lower:]') # Get first word in message, to lowercase
  if [[ "$command" =~ ^/ ]]; then # If starts with a / then it is a command
    debug "handleCommands: command: $command"
  else
    return $NO_COMMAND_HANDLED
  fi
  message=$(echo "$message" | awk '{ sub(/^[^ ]+ */, "", $0); print }') # remove /command from message

  handleBasicCommands "$command" "$message"
  local handleBasicCommandsReturn=$?
  if [[ "$handleBasicCommandsReturn" -eq "$YES_COMMAND_HANDLED" ]]; then
    return $YES_COMMAND_HANDLED
  fi

  if [[ "$model" != "user" ]]; then # If model is not an administrator
    return $NO_COMMAND_HANDLED
  fi

  handleAdminCommands "$command" "$message"
  local handleAdminCommandsReturn=$?
  if [[ "$handleAdminCommandsReturn" -eq "$YES_COMMAND_HANDLED" ]]; then
    return $YES_COMMAND_HANDLED
  fi
  return $NO_COMMAND_HANDLED
}

startRound() {
  round=("${models[@]}")
  for ((i = ${#round[@]} - 1; i > 0; i--)); do # shuffle round
    local j=$((RANDOM % (i + 1)))
    local temp=${round[i]}
    round[i]=${round[j]}
    round[j]=$temp
  done
  debug "startRound: <$(printf '%s> <' "${round[@]}" | sed 's/> <$//')>"
}

userReply() {
  if [[ "$CHAT_MODE" != "reply" ]]; then
    return
  fi
  debug "userReply"
  model="user"
  local userMessage=""
  echo -n "${COLOR_SYSTEM}<$model>${COLOR_RESET} "
  read -r userMessage < /dev/tty
  echo -ne "\033[A\r\033[K" # move 1 line up and clear line
  if [ -z "$userMessage" ]; then
    debug "No user message"
    return
  fi
  handleCommands "$userMessage"
  local handleCommandsReturn=$? # get return status code of handleCommands
  if [[ "$handleCommandsReturn" -eq "$NO_HANDLED_COMMAND" ]]; then
    addToContext "<$model> $userMessage"
    return
  fi
  # echo
  userReply # user /command handled, allow user to respond again
}

intro() {
  sendToTerminal "${COLOR_SYSTEM}\n$(banner)\n$NAME v$VERSION\n"
  local introMsg="${#models[@]} models"
  if [[ "$CHAT_MODE" == "reply" ]]; then introMsg+=", and 1 user,"; fi
  introMsg+=" invited to the chat"
  sendToTerminal "$introMsg"
  if [[ "$CHAT_MODE" == "reply" ]]; then sendToTerminal "\nUse ${TEXT_BOLD}/help${TEXT_NORMAL} for chat commands"; fi
  sendToTerminal "$COLOR_RESET"
  debug "CHAT_MODE: $CHAT_MODE"
  debug "CHAT_LOG_LINES: $CHAT_LOG_LINES"
  debug "LOG_DIR: $LOG_DIR"
  debug "DEBUG_MODE: $DEBUG_MODE"
  debug "TIMEOUT: $TIMEOUT"
  debug "TEXT_WRAP: $TEXT_WRAP"
  debug "TIME_STAMP: $TIME_STAMP"
  debug "MESSAGE_LIMIT: $MESSAGE_LIMIT"
  debug "SHOW_EMPTY: $SHOW_EMPTY"
}

allJoinTheChat() {
  if [[ "$CHAT_MODE" == "reply" ]]; then
    addToContext "*** <user> joined the chat as administrator"
  fi
  if [ -n "$topic" ]; then # if topic was set
    addToContext "*** <user> changed topic to: $topic"
  fi
  for joiningModel in "${models[@]}"; do
    addToContext "*** <$joiningModel> joined the chat"
  done
}

export OLLAMA_MAX_LOADED_MODELS=1
yesColors # Turn on ANSI color scheme
parseCommandLine "$@" # Get command line parameters
setModels
setupLogging
intro
setTopic
allJoinTheChat
setRules
saveRulesToLog
startRound
if [ -z "$models" ]; then
  notice "No models in the chat. Please /invite some models"
  CHAT_MODE="reply"
fi
while true; do
  userReply # In reply mode, user gets to respond after every model message
  if [ -z "$models" ]; then
    continue # No models in chat
  fi
  model="${round[0]}" # Get first speaker from round
  round=("${round[@]:1}") # Remove speaker from round
  if [ ${#round[@]} -eq 0 ]; then startRound; fi # If everyone has spoken, then restart round
  debug "model: <$model> -- round: <$(printf '%s> <' "${round[@]}" | sed 's/> <$//')>"
  setRules
  debug "calling: runCommandWithTimeout"
  echo -n "${COLOR_SYSTEM}*** <$model> is typing...${COLOR_RESET}"
  message=$(ollamaRunWithTimeout)
  echo -ne "\r\033[K" # clear line
  debug "called: runCommandWithTimeout"
  message=$(removeThinking "$message")
  if [ "$SHOW_EMPTY" != 1 ] && [ -z "$message" ]; then
    debug "No message from <$model> within $TIMEOUT seconds"
  else
    handleCommands "$message" && addToContext "<$model> $message"
  fi
done
exitCleanup
