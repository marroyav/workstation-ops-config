# Shell Pipes and Command Substitution

The shell connects small commands so each command can do one job well. The
most important concepts are standard output, standard input, pipes, and command
substitution.

## Standard Output and Standard Input

A command normally prints results to **standard output** (`stdout`):

```bash
fd --type f
```

That might print:

```text
README.md
src/main.py
notes/todo.txt
```

Some commands can read data from **standard input** (`stdin`). `fzf`, for
example, reads a list of choices from stdin and displays an interactive picker.

## The Pipe Operator

The pipe operator is `|`. It sends the stdout of the command on its left to the
stdin of the command on its right:

```text
command producing data | command consuming data
```

For example:

```bash
fd --type f | fzf
```

The flow is:

```text
fd finds files -> pipe carries the list -> fzf lets you select one
```

`fd` does not know anything about `fzf`, and `fzf` does not need to know how the
list was created. The pipe connects them.

Another example searches source code and then filters the result interactively:

```bash
rg -n TODO | fzf
```

## Command Substitution with `$()`

A pipe connects two running commands. Command substitution captures a
command's output and places it into another command line:

```bash
$(command)
```

Consider:

```bash
nvim "$(fd --type f | fzf)"
```

Read it from the inside out:

1. `fd --type f` prints files.
2. `|` sends those files to `fzf`.
3. `fzf` prints the one selected filename.
4. `$()` captures that filename.
5. `nvim` receives the filename and opens it.

If `src/main.py` is selected, the shell effectively runs:

```bash
nvim "src/main.py"
```

## Why the Quotes Matter

Always quote a command substitution that represents one filename:

```bash
nvim "$(fd --type f | fzf)"
```

Without quotes, a filename such as `notes/project plan.md` would be split at
the spaces and treated as multiple arguments. Quotes preserve it as one
filename.

## The Readable and Safe Version

The one-liner can be expanded into separate steps:

```bash
selected_file="$(fd --type f | fzf)"

if [ -n "$selected_file" ]; then
  nvim "$selected_file"
fi
```

This version also handles pressing Escape in `fzf`: Neovim opens only when a
file was selected.

## Pipes Versus Redirection

A pipe sends output to another command:

```bash
rg TODO | fzf
```

`>` writes output to a file, replacing that file:

```bash
rg TODO > todo-results.txt
```

`>>` appends output to a file:

```bash
date >> activity.log
```

`<` gives a file to a command as stdin:

```bash
sort < names.txt
```

## Useful Practice Examples

Choose a process interactively and display it:

```bash
ps -ef | fzf
```

Pretty-print JSON received from a web request:

```bash
curl -s https://api.github.com/repos/neovim/neovim | jq '.name, .stargazers_count'
```

Count Python files:

```bash
fd -e py | wc -l
```

Show the ten largest entries in the current directory:

```bash
du -ah . | sort -h | tail -n 10
```

Start by running each command on its own. Once its output makes sense, add the
pipe and the next command.
