# llm-council

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

## Artificial Intelligence Attogram Projects

* [ollama-multirun](https://github.com/attogram/ollama-multirun) — A bash shell script to run a single prompt against any or all of your locally installed ollama models, saving the output and performance statistics as easily navigable web pages.
* [llm-council](https://github.com/attogram/llm-council) — A bash script to start a chat between 2 or more LLMs running on ollama
* [ollama-bash-toolshed](https://github.com/attogram/ollama-bash-toolshed) — A bash script to chat with tool usage models.  Easily add new tools to your shed!
* [small-models](https://github.com/attogram/small-models) — Comparison of small open source LLMs
* [AI Test Zone](https://github.com/attogram/ai_test_zone) — Demos hosted on https://attogram.github.io/ai_test_zone/
