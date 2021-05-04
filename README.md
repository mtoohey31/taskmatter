# TaskMatter

A task management tool built to work for _me_ that stores tasks as markdown files with properties in their front-matter: this tool might not work for you. If it turns out this system doesn't work for you, but you're looking for something similar, check out dstask and its [alternatives list](https://github.com/naggie/dstask#alternatives).

## Task Properties

All task properties are stored under the `_tm` key in the markdown file's YAML front-matter, which includes an underscore in an attempt to indicate that the key should not be modified by other programs, using [Python's private variable syntax](https://docs.python.org/3/tutorial/classes.html#private-variables).

| Property  | Significance                               |
| --------- | ------------------------------------------ |
| `planned` | The date you plan to complete the task by. |
| `due`     | The date on which the task is due.         |
| `done`    | Whether the task is finished               |

## Commands

| Command    | Result                                                        |
| ---------- | ------------------------------------------------------------- |
| `week`/`w` | List all tasks planned or due for this week.                  |
| `add`/`a`  | Add a new task with the specified name. (Not yet implemented) |
| `edit`/`e` | Edit the task with the specified id.                          |
| `done`/`d` | Mark the task with the specified id as done.                  |

## Syncing

Tasks are structured as markdown files in specific directories on purpose so that git can be used to sync the tasks within an existing repository. As of now, the recommended syncing method is to manually manage a git repository of the folder where the tasks are stored.
