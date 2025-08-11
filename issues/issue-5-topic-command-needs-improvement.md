# Issue #5: /topic command needs improvement

The `/topic` command does not differentiate between user and model input. If a user types `/topic` without a topic, it shows an error "No topic to set". This is correct. However, if a model generates `/topic` without a topic, it also generates this error, which is not ideal. The code contains a `TODO` comment acknowledging this. The script should handle the user case with an error, but perhaps ignore the model's malformed command.
