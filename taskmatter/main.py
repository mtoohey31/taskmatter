#!/usr/bin/env python3

import os
import re
from typing import Union, Any
from io import BytesIO
import random as rd
import argparse as ap
import argcomplete as ac
import datetime as dt
import monthdelta as md
import frontmatter as fm
import yaml
from dateparser.date import DateDataParser as ddp
from warnings import filterwarnings

filterwarnings(
    "ignore",
    message="The localize method is no longer necessary, as this time zone supports the fold attribute",
)

# TODO: compile to cython

DEFAULT_CONFIG = {'default_path': ['./']}


def _get_config() -> dict:
    """Determine if the user has created a configuration file, merge it with the
    default config, and return it."""
    # Expand the potential config paths
    config_paths = [os.path.join(os.path.expanduser('~'),
                                 '.config/taskmatter/config.yaml'),
                    os.path.join(os.path.expanduser('~'),
                                 '.config/taskmatter/config.yml')]
    # Check each config path
    for path in config_paths:
        # If the file exists...
        if os.path.isfile(path):
            # ...then read it, load the yaml content, and if it is non-empty,
            # merge it with the default config
            with open(path, 'r') as file:
                user_config = yaml.full_load(file)
                if user_config is None:
                    return DEFAULT_CONFIG
                else:
                    # TODO: Add more advanced configuration options, and
                    # implement more advanced configuration merging to account
                    # for nested data structures in the yaml
                    return {**DEFAULT_CONFIG, **user_config}

    # If no config paths were found, just return the default config
    return DEFAULT_CONFIG


def _get_args() -> ap.Namespace:
    """Get the arguments provided by the user at the command line."""
    config = _get_config()

    parser = ap.ArgumentParser(prog="taskmatter",
                               description='process tasks in Markdown YAML '
                               'frontmatter.')
    subparsers = parser.add_subparsers(title='subcommands')
    parser.set_defaults(func=month, next=0, all=None, non_recursive=None,
                        notrim=None, paths=config['default_path'])

    week_parser = subparsers.add_parser('week', aliases=['w'],
                                        help="show tasks due this week")
    week_parser.add_argument(
        "paths", nargs='*', default=config['default_path'])
    week_parser.add_argument('-n', dest="next", default=0, type=int,
                             metavar="INT", help="offset INT weeks from today")
    week_parser.add_argument(
        '-a', action=ap.BooleanOptionalAction, dest="all",
        help="also show completed tasks")
    week_parser.add_argument(
        '-R', action=ap.BooleanOptionalAction, dest="non_recursive",
        help="don't search for tasks recursively")
    week_parser.add_argument(
        '-T', action=ap.BooleanOptionalAction, dest="notrim",
        help="don't cut off empty days")
    week_parser.set_defaults(func=week)

    month_parser = subparsers.add_parser(
        'month', aliases=['m'], help="show tasks due this month")
    month_parser.add_argument(
        "paths", nargs='*', default=config['default_path'])
    month_parser.add_argument('-n', dest="next", default=0, type=int,
                              metavar="INT",
                              help="offset INT months from today")
    month_parser.add_argument(
        '-a', action=ap.BooleanOptionalAction, dest="all",
        help="also show completed tasks")
    month_parser.add_argument(
        '-R', action=ap.BooleanOptionalAction, dest="non_recursive",
        help="don't search for tasks recursively")
    month_parser.add_argument(
        '-T', action=ap.BooleanOptionalAction, dest="notrim",
        help="don't cut off empty weeks")
    month_parser.set_defaults(func=month)

    someday_parser = subparsers.add_parser('someday', aliases=['s'],
                                           help="show tasks without planned "
                                           "or due dates")
    someday_parser.add_argument(
        "paths", nargs='*', default=config['default_path'])
    someday_parser.add_argument(
        '-a', action=ap.BooleanOptionalAction, dest="all",
        help="also show completed tasks")
    someday_parser.add_argument(
        '-R', action=ap.BooleanOptionalAction, dest="non_recursive",
        help="don't search for tasks recursively")
    someday_parser.set_defaults(func=someday)

    add_parser = subparsers.add_parser('add', aliases=['a'],
                                       help="add a new task in the current "
                                       "directory")
    add_parser.add_argument("title")
    add_parser.add_argument("props", nargs="*")
    add_parser.set_defaults(non_recursive=None)
    add_parser.set_defaults(func=add)

    edit_parser = subparsers.add_parser('edit', aliases=['e'],
                                        help="edit the specified task")
    edit_parser.add_argument("targets", nargs='+')
    edit_parser.add_argument(
        '-R', action=ap.BooleanOptionalAction, dest="non_recursive",
        help="don't search for tasks recursively")
    edit_parser.set_defaults(func=edit)

    done_parser = subparsers.add_parser('done', aliases=['d'],
                                        help="mark the specified task as done")
    done_parser.add_argument("targets", nargs='+')
    done_parser.add_argument(
        '-r', action=ap.BooleanOptionalAction, dest="recursive",
        help="search for tasks recursively")
    done_parser.set_defaults(func=done)

    # TODO: add rename subcommand that gets the title
    # TODO: add delete subcommand
    # TODO: add custom completers to subcommands that require them

    ac.autocomplete(parser)

    return parser.parse_args()


def _get_fm(args: ap.Namespace) -> list[dict]:
    """Using the _get_paths helper function, find the selected files and read
    their frontmatter, filtering out files that are not valid tasks."""
    paths = []
    _get_paths(paths, args.paths, args)

    info = {file: _get_info(file) for file in paths}
    # Filter the files by those whose info was found and who have the proper
    # extensions.
    tm_files = [file for file in paths if os.path.isfile(
        file) and os.path.splitext(file)[1] in ['.md', '.pmd', '.rmd', '.Rmd']
        and info[file] is not None]

    # Load the frontmatter for each file and create a dictionary including the
    # file's path, title, and id
    frontmatter_so_far = []
    for tm_file in tm_files:
        # TODO: Handle failures to load by printing file name but not exiting
        curr_frontmatter = fm.load(tm_file)
        if curr_frontmatter is not None and '_tm' in curr_frontmatter and curr_frontmatter['_tm'] is not None:

            frontmatter_so_far.append({**curr_frontmatter['_tm'],
                                       **{"__path__": tm_file},
                                       **info[tm_file]})  # type: ignore
        else:
            frontmatter_so_far.append(
                {**{"__path__": tm_file}, **info[tm_file]})  # type: ignore

    return frontmatter_so_far


def _get_paths(paths: list[str], input_paths: list[str],
               args: ap.Namespace) -> None:
    """Using the provided arguments, determine which paths are potential tasks
    in the scope of the user's command."""
    # NOTE: this function could be simplified by only using a single for loop
    # and calling itself recursively faster, but then the recursive argument
    # couldn't be used correctly while also being able to specify both
    # directories and files in the arguments

    # Check each provided path
    for path in input_paths:
        # Check whether the path is a file
        if os.path.isfile(path):
            paths.append(path)
        else:
            # If it's not a file, iterate through each path inside the
            # directory
            for sub_path in os.listdir(path):
                # If the path is a file, add it to the paths
                if args.non_recursive and os.path.isfile(sub_path):
                    paths.append(sub_path)
                # Otherwise, if the recursive argument was passed, call this
                # method recursively
                else:
                    _get_paths(paths, [os.path.join(path, sub_path)], args)


def _get_info(path: str) -> Union[dict[str, str], None]:
    """If the file matches the required pattern, return a dict containing the
    title and id of the file."""
    # Strip the directories and extension from the path
    stem = os.path.splitext(os.path.basename(path))[0]

    # TODO: Check for id conflicts here and resolve them with a helper function

    # Check if the stem matches the regex for an id
    if re.match(r'^.* \| [a-z]{3}$', stem):
        return {"__title__": re.sub(r' \| [a-z]{3}$', '', stem),
                "__id__": re.sub(r'^.* \| (?=[a-z]{3}$)', '', stem)}
    else:
        return None


def main() -> None:
    """The main function of the program."""
    # TODO: Refactor so that the provided args are passed to the functions as
    # actual arguments instead of as a single object, so that taskmatter can
    # be imported, and the public functions called directly without having to
    # create an argparse.Namespace object
    # TODO: Support colour coding by name of git repositories
    args = _get_args()
    args.func(args)


def _format_task(task: dict[str, Any], timeless=False) -> str:
    # TODO: Change colour of task based on whether its time has passed or is
    # today, as well as whether it's complete
    task_str_so_far = '[' + task['__id__'] + '] ' + task['__title__']
    if not timeless:
        parser = ddp(settings={'RETURN_TIME_AS_PERIOD': True})
        task_time = parser.get_date_data(
            task['planned'] if 'planned' in task else task['due'])

        if task_time.date_obj is None:
            return task_str_so_far

        if task_time.period == 'time' and task_time.date_obj.minute == 0 and \
                task_time.date_obj.second == 0:
            time_string = task_time.date_obj.strftime('%-I %p')
            if time_string == "12 PM":
                task_str_so_far += ' - Noon'
            elif time_string == "12 PM":
                task_str_so_far += ' - Midnight'
            else:
                task_str_so_far += ' - ' + time_string
        elif task_time.period == 'time' and task_time.date_obj.second == 0:
            task_str_so_far += ' - ' + \
                task_time.date_obj.strftime('%-I:%M %p')
        elif task_time.period == 'time':
            task_str_so_far += ' - ' + \
                task_time.date_obj.strftime('%-I:%M:%S %p')

    return task_str_so_far


def _get_fm_map(frontmatter: list[dict]) -> dict[dt.date, list[dict]]:
    """Transform the provided frontmatter from a list of tasks to a mapping of
    dates to lists of tasks."""
    frontmatter_map = {}

    # add date objects to tasks
    parser = ddp(settings={'RETURN_TIME_AS_PERIOD': True})
    for task in frontmatter:
        if 'planned' in task:
            res = parser.get_date_data(task['planned'])

            if res.date_obj is not None:
                task['__date__'] = res
            else:
                continue
        elif 'due' in task:
            res = parser.get_date_data(task['due'])

            if res.date_obj is not None:
                task['__date__'] = res
            else:
                continue
        else:
            continue

        day = task['__date__'].date_obj.date()  # type: ignore
        if day not in frontmatter_map:
            frontmatter_map[day] = [task]
        else:
            frontmatter_map[day].append(task)

    return frontmatter_map


def week(args: ap.Namespace) -> None:
    """The function corresponding to the `week` subcommand which prints the
    incomplete tasks for this week, or all tasks for this week if `-a` is
    specified."""
    # TODO: Handle repeated tasks

    frontmatter = _get_fm(args)

    today = dt.datetime.today().date()
    weekday = today.isoweekday()

    # NOTE: cause weeks start on Sunday, fight me
    if weekday == 7:
        weekday = 0

    week_start = dt.date(today.year, today.month, today.day) + \
        dt.timedelta(days=(7 * int(args.next)) - weekday)

    frontmatter_map = _get_fm_map(frontmatter)
    week = []

    for day_offset in range(7):
        day_start = week_start + dt.timedelta(days=day_offset)
        if day_start in frontmatter_map:
            week.append({'day': day_start.strftime(
                '%A, %b %-d'), 'tasks': [_format_task(task) for task in
                                         frontmatter_map[day_start] if 'done' not in task or not
                                         task['done'] or args.all]})
        else:
            week.append({'day': day_start.strftime('%A, %b %-d'),
                         'tasks': []})

    if not args.notrim:
        while week and not week[0]['tasks']:
            week.pop(0)

        while week and not week[-1]['tasks']:
            week.pop()

    if week:
        print(_format_week_table(week))


def _format_week_table(week: list[dict[str, Any]]) -> str:
    block_height = max([len(day['tasks']) for day in week], default=0)
    for day in week:
        day['tasks'].extend([''] * (block_height - len(day['tasks'])))
    for day in week:
        day['width'] = max([len(task)
                           for task in day['tasks']] + [len(day['day'])])
        day['day'] = day['day'] + ' ' * (day['width'] - len(day['day']))
        for i in range(len(day['tasks'])):
            day['tasks'][i] = day['tasks'][i] + ' ' * \
                (day['width'] - len(day['tasks'][i]))

    table_so_far = '┌' + '┬'.join(['─' * day['width'] for day in week]) + '┐'
    table_so_far += '\n│' + '│'.join([day['day'] for day in week]) + '│'
    table_so_far += '\n├' + \
        '┼'.join(['─' * day['width'] for day in week]) + '┤'
    for i in range(block_height):
        table_so_far += '\n│' + \
            '│'.join([day['tasks'][i] for day in week]) + '│'

    table_so_far += '\n└' + \
        '┴'.join(['─' * day['width'] for day in week]) + '┘'
    return table_so_far


def month(args: ap.Namespace) -> None:
    """The function corresponding to the `month` subcommand which prints the
    incomplete tasks for this month, or all tasks for this month if `-a` is
    specified."""
    # TODO: Handle repeated tasks

    frontmatter = _get_fm(args)

    today = dt.datetime.today().date()
    target = today + md.monthdelta(args.next)
    month_start_weekday = dt.date(
        target.year, target.month, 1).isoweekday()
    month_start = dt.date(target.year, target.month, 1) - \
        dt.timedelta(days=month_start_weekday)
    month_end_weekday = (dt.date(target.year, target.month, 1) +
                         md.monthdelta(1) - dt.timedelta(days=1)).isoweekday()
    month_end = (dt.date(target.year, target.month, 1) +
                 md.monthdelta(1) + dt.timedelta(days=6 - month_end_weekday))

    curr_sunday = month_start
    sundays = [curr_sunday]
    curr_sunday += dt.timedelta(days=7)
    while curr_sunday < month_end:
        sundays.append(curr_sunday)
        curr_sunday += dt.timedelta(days=7)

    frontmatter_map = _get_fm_map(frontmatter)
    month = []

    for week_start in sundays:

        week = []

        for day_offset in range(7):
            day_start = week_start + dt.timedelta(days=day_offset)
            if day_start in frontmatter_map:
                week.append({'day': day_start.strftime('%-d'),
                             'tasks': [_format_task(task) for task in
                                       frontmatter_map[day_start] if 'done' not in task or not
                                       task['done'] or args.all]})
            else:
                week.append({'day': day_start.strftime('%-d'),
                             'tasks': []})

        month.append(week)

    weekdays = [{'day': (month_start + dt.timedelta(days=i)).strftime('%A')}
                for i in range(7)]

    if not args.notrim:
        while month and weekdays and not any(week[0]['tasks']
                                             for week in month):
            for week in month:
                week.pop(0)
            weekdays.pop(0)

        while month and weekdays and not any(week[-1]['tasks']
                                             for week in month):
            for week in month:
                week.pop()
            weekdays.pop()

        while month and not any(day['tasks'] for day in month[0]):
            month.pop(0)

        while month and not any(day['tasks'] for day in month[-1]):
            month.pop()

    if month:
        print(
            _format_month_table(month, weekdays, month_start.strftime('%B')))


def _format_month_table(month: list[list[dict[str, Any]]], weekdays: list[dict],
                        month_name: str) -> str:
    for week in month:
        block_height = max([len(day['tasks']) for day in week], default=0)
        for day in week:
            day['tasks'].extend([''] * (block_height - len(day['tasks'])))

    for i in range(len(month[0])):
        weekdays[i]['width'] = max(
            max([len(task) for task in week[i]['tasks']] +
                [len(week[i]['day'])] + [len(weekdays[i]['day'])])
            for week in month)
        weekdays[i]['day'] += ' ' * \
            (weekdays[i]['width'] - len(weekdays[i]['day']))
        for week in month:
            week[i]['day'] = ' ' * \
                (weekdays[i]['width'] - len(week[i]['day'])) + week[i]['day']
            for j in range(len(week[i]['tasks'])):
                week[i]['tasks'][j] += ' ' * \
                    (weekdays[i]['width'] - len(week[i]['tasks'][j]))

    total_width = sum([weekday['width'] for weekday in weekdays]) + \
        len(weekdays) + 1
    table_so_far = '┌' + '─' * (total_width - 2) + '┐'
    table_so_far += '\n│' + month_name + ' ' * \
        (total_width - 2 - len(month_name)) + '│'
    table_so_far += '\n├' + \
        '┬'.join(['─' * weekday['width'] for weekday in weekdays]) + '┤'
    table_so_far += '\n│' + '│'.join([weekday['day']
                                     for weekday in weekdays]) + '│'
    for week in month:
        table_so_far += '\n├' + \
            '┼'.join(['─' * weekday['width'] for weekday in weekdays]) + '┤'
        table_so_far += '\n│' + \
            '│'.join(['\x1b[1m' + task['day'] +
                     '\x1b[0m' for task in week]) + '│'
        if len(week[0]['tasks']) != 0:
            for i in range(len(week[0]['tasks'])):
                table_so_far += '\n│' + \
                    '│'.join([task['tasks'][i] for task in week]) + '│'
    table_so_far += '\n└' + \
        '┴'.join(['─' * weekday['width'] for weekday in weekdays]) + '┘'

    return table_so_far


def someday(args: ap.Namespace) -> None:
    """The function corresponding to the `someday` subcommand which prints the
    incomplete tasks without planned or due dates, or all tasks without planned
    or due dates if `-a` is specified."""
    # TODO: Handle repeated tasks

    frontmatter = _get_fm(args)

    filtered_frontmatter = [task for task in frontmatter if ('done' not in task
                                                             or not
                                                             task['done'] or
                                                             args.all) and
                            ('due' not in task and 'planned' not in task)]

    for formatted_task in [_format_task(task, True) for task in
                           filtered_frontmatter]:
        print(formatted_task)


def add(args: ap.Namespace) -> None:
    """The function corresponding to the `add` command that creates a new task
    with the given title."""
    # Get all the paths within the current directory
    paths = []
    _get_paths(paths, ['./'], args)

    # Also get the info regarding each of the paths within the current directory
    info = {file: _get_info(file) for file in paths}

    # Create a random id and check that it is not already present in the
    # current directory. It is possible to run into id conflicts with this
    # method, as the length of ids is quite low to keep filenames readable,
    # however, even if we were to check recursively or even in parent
    # directories for objects with similar names, there would still be a
    # possibility of id conflicts when adding task lists from other computers
    # for example, so they have to be resolved by the list methods.
    id = ''.join([chr(rd.randint(97, 122)) for _ in range(3)])
    while id in [info[file]['__id__'] for file in info  # type: ignore
                 if info[file] is not None]:
        id = ''.join([chr(rd.randint(97, 122)) for _ in range(3)])

    props = {}
    # Iterate through each provided prop in the arguments
    for prop in args.props:
        split_props = re.split(r'(?<!\\):', prop)
        # Test if the properties arguments can be suitably divided by `:`
        # Raise an error if it does not have enough divisions
        if len(split_props) < 2:
            raise ValueError('Properties key and value arguments must be '
                             'separated by `:`')
        # Otherwise, assign the key and value variables, removing whitespace
        # from the ends
        elif len(split_props) == 2:
            key, value = [s.strip() for s in split_props]
        else:
            key = split_props[0].strip()
            value = ':'.join(split_props[1:]).strip()

        # If the property is `done`, then try to parse it as a boolean.
        if key == 'done':
            if value in ['True', 'true', 'Yes', 'yes', 'Y', 'y', 1]:
                props[key] = True
            elif value in ['False', 'false', 'No', 'no', 'N', 'n', 0]:
                props[key] = False
            else:
                # If this fails, then raise an error
                raise ValueError('The `done` property must be a boolean value')
            # Otherwise, skip all further processing of this property and
            # proceed to the next argument
            continue

        # Next, try to parse any argument as a boolean, but less aggressively,
        # and allow failure
        if value in ['True', 'true', 'Yes', 'yes', 'Y', 'y']:
            props[key] = True
            continue
        elif value in ['False', 'false', 'No', 'no', 'N', 'n']:
            props[key] = False
            continue

        # Next, try to parse the value as a number, first int then float
        try:
            props[key] = int(value)
            continue
        except ValueError:
            pass
            try:
                props[key] = float(value)
                continue
            except ValueError:
                pass

        # Attempt to parse the value as a date, including the time as a period
        parser = ddp(settings={'RETURN_TIME_AS_PERIOD': True})
        date = parser.get_date_data(value)
        # Only raise an error if the date cannot be parsed if the property is
        # 'planned' or 'due'
        if date.date_obj is None and key in ['planned', 'due']:
            raise ValueError(
                f'Provided `{key}` value could not be parsed as a date')
        # Otherwise, if it wasn't one of those properties and could not be
        # parsed, simply continue with the property as the raw string
        elif date.date_obj is None:
            props[key] = value
        # Otherwise, if it was successfully parsed return a string, formatted
        # to match the period of date so that unnecessarily precise values are
        # not included
        else:
            if date.period == 'time':
                if date.date_obj.second == 0:
                    props[key] = date.date_obj.strftime(
                        '%B %-d, %Y, %-I:%M %p')
                else:
                    props[key] = date.date_obj.strftime(
                        '%B %-d, %Y, %-I:%M:%S %p')
            else:
                props[key] = date.date_obj.strftime('%B %-d, %Y')

    # Dump the properties to a file, setting the contents to a level 1 ATX
    # header that is the title of the task
    f = BytesIO()
    if props:
        fm.dump(fm.Post(f'# {args.title}', **{'_tm': props}), f)
    else:
        fm.dump(fm.Post(f'# {args.title}', **{'_tm': None}), f)

    with open(f'./{args.title} | {id}.md', 'w') as file:
        file.write(f.getvalue().decode('utf8') + '\n')


def edit(args: ap.Namespace) -> None:
    """The function corresponding to the `edit` subcommand that edits the tasks
    with the given targets."""
    # TODO: Handle recursive/non-recursive possibilities better by starting
    # with a non-recursive check, informing the user if that did not succeed,
    # then proceeding to a recursive check
    frontmatter = _get_fm(args)

    # Iterate through each target provided
    for target in args.targets:
        # First check if the target is an id, if so, use the gathered
        # frontmatter to find the corresponding path
        if re.match(r'^[a-z]{3}$', target):
            for item in frontmatter:
                if item['__id__'] == target:
                    # Once the id has been found, try to use the shell's visual
                    # or editor variables to edit the files
                    os.system('$VISUAL "' + item['__path__'] + '" || $EDITOR "'
                              + item['__path__'] + '"')
                    break
            else:
                # If the id is never found, inform the user
                print(f'No task with id: "{target}" found')
        # If the target is not an id, but is a valid path, edit it
        elif os.path.exists(target):
            os.system(f'$VISUAL "{target}" || $EDITOR "{target}"')
        # Otherwise if none of the above worked, inform the user that the
        # target was not found
        else:
            print(f'Could not find task "{target}"')


def done(args: ap.Namespace) -> None:
    """The function corresponding to the `done` command that marks the tasks
    with the given targets as done."""
    # TODO: Handle recursive/non-recursive possibilities better by starting
    # with a non-recursive check, informing the user if that did not succeed,
    # then proceeding to a recursive check
    frontmatter = _get_fm(args)

    # Iterate through each target provided
    for target in args.targets:
        # First check if the target is an id, if so, use the gathered
        # frontmatter to find the corresponding path
        if re.match(r'^[a-z]{3}$', target):
            for item in frontmatter:
                if item['__id__'] == target:
                    # Once the target has been found, load the file with then
                    # frontmatter module, merge a `done: true` property with
                    # the frontmatter's `_tm` property, or inform the user
                    # if this was not possible, then write the file
                    f = BytesIO()
                    file_fm = fm.load(item['__path__'])
                    if '_tm' in file_fm and isinstance(file_fm['_tm'], dict):
                        file_fm['_tm']['done'] = True
                    elif '_tm' in file_fm and file_fm['_tm'] is not None:
                        raise ValueError(
                            f'{target} contains unsupported `_tm` key')
                    else:
                        file_fm['_tm'] = {'done': True}
                    fm.dump(file_fm, f)

                    with open(item['__path__'], 'w') as file:
                        file.write(f.getvalue().decode('utf8') + '\n')

                    break
            else:
                print(f'No task with id: "{target}" found')
        # If the target is not an id, but is a valid path, use the same logic
        # as in the past case to merge properties and write the file
        elif os.path.exists(target):
            f = BytesIO()
            file_fm = fm.load(target)
            if '_tm' in file_fm and \
                    (isinstance(file_fm['_tm'], dict)
                     or file_fm['_tm'] is None):
                file_fm['_tm']['done'] = True
            elif '_tm' in file_fm:
                raise ValueError(
                    f'{target} contains unsupported `_tm` key')
            else:
                file_fm['_tm'] = {'done': True}
            fm.dump(file_fm, f)

            with open(target, 'w') as file:
                file.write(f.getvalue().decode('utf8') + '\n')
        # Otherwise if none of the above worked, inform the user that the
        # target was not found
        else:
            print(f'Could not parse task "{target}"')


if __name__ == '__main__':
    main()
