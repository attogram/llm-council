# Issue #4: Incomplete Admin Commands

The `/kick` and `/invite` admin commands are incomplete. They contain `TODO` comments in the code, and the logic doesn't verify if a model exists or is already in the chat before performing actions. For example, you can "kick" a model that isn't in the chat, and the system will announce that the model was kicked, which is misleading.
