# taskmatter

A task management tool that stores tasks as markdown files with properties in their front-matter.

![screenshot](https://user-images.githubusercontent.com/36740602/149677423-c6cb4b8d-8098-4bfe-9ab1-ddb157708a0d.png)

## Installation

```sh
pip3 install git+https://github.com/mtoohey31/taskmatter.git#egg=taskmatter
```

See [releases](https://github.com/mtoohey31/taskmatter/releases) for shell completion files.

## Task Properties

All task properties are stored under the `_tm` key in the markdown file's YAML front-matter, which includes an underscore in an attempt to indicate that the key should not be modified by other programs, using [Python's private variable syntax](https://docs.python.org/3/tutorial/classes.html#private-variables).

| Property  | Significance                               | Data Type |
| --------- | ------------------------------------------ | --------- |
| `planned` | The date you plan to complete the task by. | String    |
| `due`     | The date on which the task is due.         | String    |
| `done`    | Whether the task is finished               | Boolean   |

## Commands

| Command   | Abbreviation | Result                                                  |
| --------- | ------------ | ------------------------------------------------------- |
| `week`    | `w`          | List all tasks planned or due this week.                |
| `month`   | `m`          | List all tasks planned or due this month.               |
| `someday` | `s`          | List all tasks with no planned or due date.             |
| `add`     | `a`          | Add a new task with the specified name and properties.  |
| `edit`    | `e`          | Edit the task(s) with the specified id or path.         |
| `done`    | `d`          | Mark the task(s) with the specified id or path as done. |

Note that `week` is the default subcommand, so when `taskmatter` is run with no arguments, it will behave identically to `taskmatter month`.

## Syncing

Tasks are structured as markdown files in specific directories on purpose so that git can be used to sync the tasks within an existing repository. As of now, the recommended syncing method is to manually manage a git repository of the folder where the tasks are stored.

## Suggestions

- Typing `taskmatter` every time is a bit much, so aliasing it to something shorter such as `tm` or `t` in your shell's startup file will likely speed up your workflow.

## Alternatives

Check out dstask and its [alternatives list](https://github.com/naggie/dstask#alternatives).
