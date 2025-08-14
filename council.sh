#!/usr/bin/env bash
#
# LLM Council
# Start a chat room between all, or some, of your models running on Ollama.
#
# Usage help: ./council.sh -h

if [ -z "$BASH_VERSION" ]; then
  echo "Error: This script requires Bash to run." >&2
  exit 1
fi
if (( ${BASH_VERSINFO[0]} < 3 || (${BASH_VERSINFO[0]} == 3 && ${BASH_VERSINFO[1]} < 2) )); then
    echo "Error: This script requires Bash version 3.2 or higher." >&2
    echo "You are using Bash version $BASH_VERSION." >&2
    exit 1
fi

NAME="llm-council"
VERSION="3.17.0"
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
MODEL_QUIT_ENABLED=1 # Models can use /quit. 0 = no, 1 = yes
TOPIC_LOCKED=0 # Topic is locked. 0 = no, 1 = yes

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
  -dmq, -disablemodelquit  Disable /quit command for models
  -lt, -locktopic    Lock the topic, models can not change it
  -v,  -version     Show version information
  -h,  -help        Help for $NAME
  [topic]           Set the chat topic (Optional)
"
}

commandHelp() {
  echo "Chat Commands:

/multi                   - Multi-line input mode
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
/mode [reply|nouser] - Set chat mode
/timeout [secs]  - Set model response timeout
/wrap [chars]    - Set text wrap
/timestamp       - Toggle timestamps
/showempty       - Toggle showing empty messages
/colors          - Toggle colors
/debug           - Toggle debug mode
/help            - This command list
"
}

setRules() {
  local topic_instruction
  if [ "$TOPIC_LOCKED" -eq 1 ]; then
    topic_instruction="The topic is locked. The current topic is: $topic"
  else
    topic_instruction="If you want to set a new topic, send ONLY the 1 line command: /topic <new topic>"
  fi
  rules="You are in a group chat with ${#models[@]} members.
You are user <${model:-user}>.
If you want to mention another user, you MUST use syntax: @username.
If you want to leave the chat, send ONLY the 1 line command: /quit <optional reason>
$topic_instruction
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
    >&2 printf "%s\n" "${COLOR_DEBUG}[$(date '+%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
  fi
}

sendToTerminal() {
  if [ "$TEXT_WRAP" -ge 1 ]; then
    printf "%b\n" "$1" | fold -s -w "$TEXT_WRAP"
  else
    printf "%b\n" "$1"
  fi
}

notice() {
  >&2 sendToTerminal "${COLOR_DEBUG}NOTICE: $1${COLOR_RESET}"
}

error() {
  >&2 sendToTerminal "${COLOR_DEBUG}ERROR: $1${COLOR_RESET}"
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
      -dmq|-disablemodelquit|--disable-model-quit) # Disable model quit
        MODEL_QUIT_ENABLED=0
        shift
        ;;
      -lt|-locktopic|--lock-topic) # Lock topic
        TOPIC_LOCKED=1
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
        if [ -n "$2" ] && [[ "$2" != -* ]]; then
          modelsList="$2"
          shift 2
        else
          error "Argument for $1 is missing" >&2
          exit $RETURN_ERROR
        fi
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
        if [ -n "$2" ] && [[ "$2" != -* ]]; then
          TIMEOUT="$2"
          shift 2
        else
          error "Argument for $1 is missing" >&2
          exit $RETURN_ERROR
        fi
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
        if [ -n "$2" ] && [[ "$2" != -* ]]; then
          TEXT_WRAP="$2"
          shift 2
        else
          error "Argument for $1 is missing" >&2
          exit $RETURN_ERROR
        fi
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
   printf "\nChat Log Started: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_DIR}/messages.txt"
}

saveRulesToLog() {
  printf "%s\n" "$rules" > "${LOG_DIR}/rules.txt"
}

saveMessageToLog() {
  printf "%s\n" "$1" >> "${LOG_DIR}/messages.txt" # append message to message log
}

addToContext() {
  local message="$1"
  message="$(showTimestamp)${message}" # optional timestamp
  if [ "$TEXT_WRAP" -ge 1 ]; then
    message=$(printf "%s\n" "$message" | fold -s -w "$TEXT_WRAP")
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
  local stderrFile=$(mktemp)
  (
    ollama run "$model" --hidethinking -- "${rules}${context}" 2> "$stderrFile"
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
  local exitCode=$?
  kill $pidOllamaTimeout 2>/dev/null
  if [ $exitCode -ne 0 ]; then
    local stderr=$(<"$stderrFile")
    if [ -n "$stderr" ]; then
      error "Ollama error for model <$model>:\n$stderr"
    fi
  fi
  rm "$stderrFile"
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
    if [[ "$CHAT_MODE" != "reply" ]]; then
      echo; echo "${COLOR_SYSTEM}*** No models remaining. Chat ending.${COLOR_RESET}"
      exit $RETURN_SUCCESS
    else
      notice "No models remaining. /invite a new model or /quit"
    fi
  fi
}

inArray() {
  local element="$1"
  shift
  local arr=("$@")
  for item in "${arr[@]}"; do
    if [[ "$item" == "$element" ]]; then
      return 0 # found
    fi
  done
  return 1 # not found
}

handleMentions() {
  local message="$1"
  local author="$2"
  local mentions
  mentions=$(echo "$message" | grep -oE '@[a-zA-Z0-9:.-]+')
  if [ -z "$mentions" ]; then
    return
  fi
  for mention in $mentions; do
    local mentioned_model=${mention:1}
    if ! inArray "$mentioned_model" "${models[@]}"; then
      debug "Mentioned model <$mentioned_model> is not in the chat."
      continue
    fi
    debug "Model <$author> mentioned <$mentioned_model>"
    if [ "$author" == "user" ]; then
      debug "User mentioned <$mentioned_model>. Moving to front of round."
      local new_round=()
      for m in "${round[@]}"; do
        if [ "$m" != "$mentioned_model" ]; then
          new_round+=("$m")
        fi
      done
      round=("${new_round[@]}")
      round=("$mentioned_model" "${round[@]}")
    else
      local chance=$((RANDOM % 100))
      debug "Mention chance: $chance"
      if [ $chance -lt 75 ]; then
        debug "Model <$mentioned_model> gets to speak next."
        local new_round=()
        for m in "${round[@]}"; do
          if [ "$m" != "$mentioned_model" ]; then
            new_round+=("$m")
          fi
        done
        round=("${new_round[@]}")
        round=("$mentioned_model" "${round[@]}")
      else
        debug "Model <$mentioned_model> was mentioned, but does not get to speak next."
      fi
    fi
    break
  done
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
      if ! inArray "$message" "${models[@]}"; then
        error "Model <$message> is not in the chat."
        return $YES_COMMAND_HANDLED
      fi
      addToContext "*** <user> kicked <$message> out of the chat"
      removeModel "$message"
      return $YES_COMMAND_HANDLED
      ;;
    /invite) # Invite a model to join the chat
      if [ -z "$message" ]; then
        error "No model specified to invite"
        return $YES_COMMAND_HANDLED
      fi
      if inArray "$message" "${models[@]}"; then
        error "Model <$message> is already in the chat."
        return $YES_COMMAND_HANDLED
      fi
      local ollamaModels=($(ollama list | awk '{if (NR > 1) print $1}'))
      if ! inArray "$message" "${ollamaModels[@]}"; then
        error "Model <$message> not found in Ollama."
        return $YES_COMMAND_HANDLED
      fi
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
    /mode)
      if [ "$message" == "reply" ]; then
        CHAT_MODE="reply"
        addToContext "*** <user> set chat mode to reply"
      elif [ "$message" == "nouser" ]; then
        CHAT_MODE="nouser"
        addToContext "*** <user> set chat mode to nouser"
      else
        error "Invalid mode. Use 'reply' or 'nouser'"
      fi
      return $YES_COMMAND_HANDLED
      ;;
    /timeout)
      if [ -z "$message" ]; then
        error "No timeout specified"
        return $YES_COMMAND_HANDLED
      fi
      if ! [[ "$message" =~ ^[0-9]+$ ]]; then
        error "Timeout must be an integer"
        return $YES_COMMAND_HANDLED
      fi
      TIMEOUT="$message"
      addToContext "*** <user> set timeout to $TIMEOUT seconds"
      return $YES_COMMAND_HANDLED
      ;;
    /wrap)
      if [ -z "$message" ]; then
        error "No wrap value specified"
        return $YES_COMMAND_HANDLED
      fi
      if ! [[ "$message" =~ ^[0-9]+$ ]]; then
        error "Wrap must be an integer"
        return $YES_COMMAND_HANDLED
      fi
      TEXT_WRAP="$message"
      addToContext "*** <user> set text wrap to $TEXT_WRAP"
      return $YES_COMMAND_HANDLED
      ;;
    /timestamp)
      if [ "$TIME_STAMP" -eq 1 ]; then
        TIME_STAMP=0
        addToContext "*** <user> disabled timestamps"
      else
        TIME_STAMP=1
        addToContext "*** <user> enabled timestamps"
      fi
      return $YES_COMMAND_HANDLED
      ;;
    /showempty)
      if [ "$SHOW_EMPTY" -eq 1 ]; then
        SHOW_EMPTY=0
        addToContext "*** <user> disabled showing empty messages"
      else
        SHOW_EMPTY=1
        addToContext "*** <user> enabled showing empty messages"
      fi
      return $YES_COMMAND_HANDLED
      ;;
    /colors)
      if [ -n "$COLOR_SYSTEM" ]; then
        noColors
        addToContext "*** <user> disabled colors"
      else
        yesColors
        addToContext "*** <user> enabled colors"
      fi
      return $YES_COMMAND_HANDLED
      ;;
    /debug)
      if [ "$DEBUG_MODE" -eq 1 ]; then
        DEBUG_MODE=0
        addToContext "*** <user> disabled debug mode"
      else
        DEBUG_MODE=1
        addToContext "*** <user> enabled debug mode"
      fi
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
      if [ "$TOPIC_LOCKED" -eq 1 ] && [ "$model" != "user" ]; then
        debug "Model <$model> tried to change topic, but it is locked."
        return $YES_COMMAND_HANDLED
      fi
      if [ -z "$message" ]; then
        if [ "$model" == "user" ]; then
          error "No topic to set"
        else
          debug "Model <$model> sent empty /topic command. Ignoring."
        fi
        return $YES_COMMAND_HANDLED
      fi
      topic="$message"
      addToContext "*** <$model> changed topic to: $message"
      return $YES_COMMAND_HANDLED
      ;;
    /quit|/leave)
      if [ "$model" != "user" ] && [ "$MODEL_QUIT_ENABLED" -eq 0 ]; then
        debug "Model <$model> tried to quit, but it is disabled."
        return $YES_COMMAND_HANDLED
      fi
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
  while true; do
    local userMessage=""
    echo -n "${COLOR_SYSTEM}<$model>${COLOR_RESET} "
    read -r userMessage < /dev/tty
    echo -ne "\033[A\r\033[K" # move 1 line up and clear line
    local trimmedMessage
    trimmedMessage=$(echo "$userMessage" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ "$trimmedMessage" == "/multi" ]]; then
      sendToTerminal "${COLOR_SYSTEM}Multi-line input mode. Press Ctrl+D on a new line when finished.${COLOR_RESET}"
      sendToTerminal "${COLOR_SYSTEM}---${COLOR_RESET}"
      userMessage=$(cat)
      sendToTerminal "${COLOR_SYSTEM}---${COLOR_RESET}"
    fi
    if [ -z "$userMessage" ]; then
      debug "No user message"
      return
    fi
    if handleCommands "$userMessage"; then
      addToContext "<$model> $userMessage"
      handleMentions "$userMessage" "$model"
      return
    fi
  done
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
    if handleCommands "$message"; then
      addToContext "<$model> $message"
      handleMentions "$message" "$model"
    fi
  fi
done
exitCleanup
