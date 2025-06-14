# llm-council
A bash script to start a chat between 2 or more LLMs running on ollama

## usage

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
