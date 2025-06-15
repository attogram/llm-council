# llm-council

A bash script to start a chat between 2 or more LLMs running on ollama

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
- To stop the council, press **Control-C**

## Other Attogram Projects
* [ollama-multirun](https://github.com/attogram/ollama-multirun) - A bash shell script to run a single prompt against any or all of your locally installed ollama models, saving the output and performance statistics as easily navigable web pages.
* [small-models](https://github.com/attogram/small-models) - Comparison of small open source LLMs
* [AI Test Zone](https://github.com/attogram/ai_test_zone) - Demos hosted on https://attogram.github.io/ai_test_zone/
