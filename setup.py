from setuptools import setup

setup(
    name='taskmatter',
    version='1.0.0',
    description='A task management tool that stores tasks as markdown files with properties in their front-matter.',
    author="Matthew Toohey",
    author_email="contact@mtoohey.com",
    packages=['taskmatter'],
    entry_points={"console_scripts": ["taskmatter = taskmatter.main:main"]}
)
