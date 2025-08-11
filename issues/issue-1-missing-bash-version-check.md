# Issue #1: Missing Bash Version Check

The script is written for bash but doesn't verify the interpreter version. It uses features like `[[...]]` and `read -ra` which require a reasonably modern version of bash (at least 3.2+). Running it with an older bash or a different shell (like `sh`) would cause errors. It is recommended to add a check at the beginning of the script to ensure the bash version is 3.2 or higher.
