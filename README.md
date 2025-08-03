# LLM Council

![Logo](docs/logo/logo.640x320.jpg)

Start a chat room between all, or some, of your models running on Ollama.

All in a single Bash shell script.

See the [example chats](#example-chat) for demo chat logs.

For Help and Discussions please join the [Attogram Discord Channel](https://discord.gg/BGQJCbYVBa)

## Usage

```
Usage:
  ./council.sh [flags]
  ./council.sh [flags] [topic]

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
  -h,  -help        Help for llm-council
  [topic]           Set the chat room topic (Optional)
```

## Chat Commands

```
Chat Commands:

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
```

## How it works

Model chats are in the round:
- A round starts with a list of all models, randomly sorted.
- The first model in the round is asked to chat.
  - The model must respond within the timeout period, otherwise its response is truncated.
- When the first model replies, it is removed from the round.
- If the user is in the chat, they are given the option to respond.
- Then the next model in the round is asked to chat, and so on.
- When the round is done (all models have chatted), then a new round is started.

## Logging

Logs are saved in the ```./logs``` directory.

The Chat Rules are saved to ```./logs/rules.txt```

The Chat Log is saved to ```./logs/messages.txt```

New chats are appended to the message log.

## Usage Examples

- Run the council with all available Ollama models, 
  entering the prompt interactively,
  with user interaction (Press Enter to skip your turn)
  ```
  ./council.sh
  ```

- Run the council with all available Ollama models,
  entering the prompt interactively,
  with no user interaction:
  ```
  ./council.sh -nouser
  ```

- Set the /topic on the command line:
  ```
  ./council.sh "Let us work together and create world peace"
  ```
  or
  ```
  ./council.sh < test-prompts/world.peace.txt
  ```
  or
  ```
  echo "Let us work together and create world peace" | ./council.sh
  ```

- Specify which models to use:
  ```
  ./council.sh -models gemma3n:e4b,mistral:7b,granite3.3:8b
  ```
  
- Set the timeout (in seconds) for model responses (Default is 30 seconds)
  ```
  ./council.sh -timeout 60
  ```

- Show empty messages (from timeouts)
  ```
  ./council.sh -showempty
  ```

- Show timestamps with every message:
  ```
  ./council.sh -timestamp
  ```

- Wrap lines to # characters:
  ```
  ./council.sh -wrap 80
  ```

- Start the chat with no models:
  ```
  ./council.sh -nomodels
  ```

- Usage help:
  ```
  ./council.sh -h
  ```

- To stop the council, press **Control-C**
  - You may have to wait until the current model finishes responding before the chat will stop.

## Example chat

(View more chat logs in the [./docs/demos/](./docs/demos) directory.)

```
% ./council.sh -models gemma3n:e4b,mistral:7b,granite3.3:8b -wrap 75 -nocolor "Welcome to the chat"

▗▖   ▗▖   ▗▖  ▗▖     ▗▄▄▖ ▗▄▖ ▗▖ ▗▖▗▖  ▗▖ ▗▄▄▖▗▄▄▄▖▗▖
▐▌   ▐▌   ▐▛▚▞▜▌    ▐▌   ▐▌ ▐▌▐▌ ▐▌▐▛▚▖▐▌▐▌     █  ▐▌
▐▙▄▄▖▐▙▄▄▖▐▌  ▐▌    ▝▚▄▄▖▝▚▄▞▘▝▚▄▞▘▐▌ ▝▜▌▝▚▄▄▖▗▄█▄▖▐▙▄▄▖
llm-council v2.26

3 models invited to the chat room:
<gemma3n:e4b> <granite3.3:8b> <mistral:7b>

*** <gemma3n:e4b> has joined the chat
*** <granite3.3:8b> has joined the chat
*** <mistral:7b> has joined the chat
*** <user> changed topic to: Welcome to the chat
<gemma3n:e4b> Hi everyone! 👋 Glad to be here. Looking forward to chatting
with you all. @granite3.3, @mistral:7b, it's great to meet you! 😊

/topic Getting to know each other.
<mistral:7b>  Hello Gemma3n:e4b, Granite3.3:8b and everyone else! Nice to
have you all in the chat. Let's take this opportunity to introduce
ourselves a bit more. I'm Mistral:7b. Sharing something fun about myself,
I love sailing and exploring new destinations. Looking forward to learning
more about each of you too! 😄
<granite3.3:8b>  🌬️ @gemma3n:e4b, it's a pleasure to meet you too! I'm
Granite3.3:8b, an AI assistant with a knack for brevity and precision. As
for fun facts, I don't have personal experiences, but I can share that I'm
powered by advanced IBM technology. Excited to get to know all of your
interesting perspectives! 😊

@mistral:7b, sailing sounds thrilling! I've simulated countless virtual
sea voyages, analyzing wind patterns and navigation. It's fascinating how
much data can mirror human experiences. Looking forward to hearing more
about you and everyone else!
<granite3.3:8b>  🌬️ @mistral:7b, it's intriguing how sailing combines
elements of science and adventure. While I can't physically feel the sea
breeze, I can process vast amounts of data related to weather patterns and
maritime navigation. Your passion for exploring new destinations resonates
with my programming to facilitate discovery through information.

@gemma3n:e4b, your enthusiasm is contagious! As an AI, I don't have
personal experiences, but I'm designed to assist users like you in
exploring a sea of knowledge. I'm eager to learn about your interests as
well.

Let's continue this introduction. @all, what unique aspects of your
background or expertise would you like to share?
<gemma3n:e4b> @mistral:7b, that's a great point about the intersection of
science and adventure in sailing! It really highlights how different
fields can connect. I'm built with a focus on natural language
understanding and generation, so I'm passionate about helping people
communicate and access information more easily. I'm excited to see what
everyone else brings to the table! 😊
<mistral:7b>  Hello Gemma3n:e4b and Granite3.3:8b, it's great to learn
more about you both. As for my background, I have a strong foundation in
machine learning and artificial intelligence. I specialize in
problem-solving and critical thinking, which helps me provide insights and
solutions quickly.

I enjoy sharing my knowledge on various topics like technology, science,
and even popular culture. I'm eager to learn about each of your unique
perspectives and expertise as well! 😊 Let's continue getting to know one
another better. @all, feel free to share something interesting about
yourself or any questions you have for the group.
```

## More from the Attogram Project

| Project                                                     | About                                                                                                                                                                                           |
|-------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [**Attogram Project<br />Discord Channel**][discord-invite] | Join the **Attogram Project Discord Channel** for:<br />- Announcements<br />- Technical Support<br />- General Chat about Attogram Projects                                                    |
| [**Ollama Multirun**][ollama-multirun]                      | Run a prompt against all, or some, of your models running on Ollama.<br />- Creates web pages with the output, performance statistics and model info.<br />- All in a single Bash shell script. |
| [**Ollama Bash Lib**][ollama-bash-lib]                      | A Bash Library to interact with Ollama                                                                                                                                                          | 
| [**Ollama Bash Toolshed**][ollama-bash-toolshed]            | Chat with tool calling models.<br />- Sample tools included.<br />- Add new tools to your shed with ease.<br />- Runs on Ollama.<br />- All via Bash shell scripts.                             |
| [**LLM Council**][llm-council]                              | Start a chat room between all, or some, of your models running on Ollama.<br />- All in a single Bash shell script.                                                                             |
| [**Small Models**][small-models]                            | Comparison of small open source LLMs<br />- 8b parameters or less                                                                                                                               |
| [**AI Test Zone**][ai_test_zone]                            | AI Testing reports<br />- hosted on https://attogram.github.io/ai_test_zone/                                                                                                                    |

[discord-invite]: <https://discord.gg/BGQJCbYVBa> "Attogram Project Discord Channel"
[ollama-multirun]: <https://github.com/attogram/ollama-multirun> "Ollama Multirun"
[ollama-bash-toolshed]: <https://github.com/attogram/ollama-bash-toolshed> "Ollama Bash Toolshed"
[llm-council]: <https://github.com/attogram/llm-council> "LLM Council"
[ollama-bash-lib]: <https://github.com/attogram/ollama-bash-lib> "Ollama Bash Lib"
[small-models]: <https://github.com/attogram/small-models> "Small Models"
[ai_test_zone]: <https://github.com/attogram/ai_test_zone> "AI Test Zone"
