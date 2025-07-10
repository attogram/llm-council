# LLM Council

![Logo](docs/logo/logo.640x320.jpg)

A bash script to start a chat room between all, or some, of your models running on ollama.

You set the initial topic, then the models take over.

Models may use these commands:
- ```/topic <new topic>```
  - shows topic change to the room
  - sets the topic into the chat instructions
- ```/quit```
- ```/quit <reason>```
  - shows leaving message to the room
  - removes model from the chat

## Usage

- Run the council with all available ollama models, entering prompt interactively:
  ```
  ./council.sh
  ```

- Run the council with all available ollama models, entering prompt on command line:
  ```
  ./council.sh "Let us work together and create world peace"
  ```
    
- Specify which models to use in the council:
  ```
  ./council.sh -m model1,model2,model3,model4
  ```

- Set the timeout (in seconds)
  ```
  ./council.sh -t 30
  ```
  
- To stop the council, press **Control-C**

## More from the Attogram Project

| Project          | Github Repo                                  | Description                                                                                                                                                                                 |
|------------------|----------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Multirun**     | [ollama-multirun][ollama-multirun]           | Run a prompt against all, or some, of your models running on Ollama.<br />Creates web pages with the output, performance statistics and model info.<br />All in a single Bash shell script. |
| **Toolshed**     | [ollama-bash-toolshed][ollama-bash-toolshed] | Chat with tool calling models.<br />Sample tools included.<br />Add new tools to your shed with ease.<br />Runs on Ollama.<br />All via Bash shell scripts.                                 |
| **LLM Council**  | [llm-council][llm-council]                   | Start a chat room between all, or some, of your models running on Ollama.<br />All in a single Bash shell script.                                                                           |
| **Small Models** | [small-models][small-models]                 | Comparison of small open source LLMs (8b parameters or less)                                                                                                                                |
| **AI Test Zone** | [ai_test_zone][ai_test_zone]                 | Test results hosted on https://attogram.github.io/ai_test_zone/                                                                                                                             |

[llm-council]: <https://github.com/attogram/llm-council> "LLM Council"
[ollama-bash-toolshed]: <https://github.com/attogram/ollama-bash-toolshed> "Ollama Bash Toolshed"
[ollama-multirun]: <https://github.com/attogram/ollama-multirun> "Ollama Multirun"
[small-models]: <https://github.com/attogram/small-models> "Small Models"
[ai_test_zone]: <https://github.com/attogram/ai_test_zone> "AI Test Zone"

