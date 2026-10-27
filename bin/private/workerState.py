#!/usr/bin/env python3
"""Observe one launched Gem without trusting a stale PID or readiness file."""
import argparse
import json
from pathlib import Path
import subprocess


def observe(directory, runner):
    launch_file = directory / 'launch.json'
    if not launch_file.exists():
        return {'state': 'stopped', 'live': False}
    try:
        launch = json.loads(launch_file.read_text())
        pid, token = int(launch['pid']), launch['token']
        if pid <= 1 or not isinstance(token, str) or not token:
            raise ValueError('Invalid launch identity')
        process = subprocess.run(['ps', '-ww', '-p', str(pid), '-o', 'command='],
                                 text=True, capture_output=True, check=False)
        if process.stderr.strip():
            raise RuntimeError(process.stderr.strip())
        live = process.returncode == 0 and process.stdout.rstrip().endswith(' -S ' + str(runner))
        result = {'state': 'starting' if live else 'exited', 'live': live,
                  'pid': pid, 'token': token}
        try:
            native = json.loads((directory / 'state.json').read_text())
            if native.get('pid') == pid and native.get('token') == token:
                result['nativeState'] = native.get('state')
                if live and native.get('state') == 'stopped':
                    result['state'] = 'stopping'
                elif live or native.get('state') in ('stopped', 'failed', 'cleanupPending'):
                    result['state'] = native.get('state', 'unknown')
        except (FileNotFoundError, json.JSONDecodeError):
            pass  # The Gem may be creating its first readiness observation.
        return result
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        return {'state': 'unknown', 'live': None, 'error': str(error)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('runner', type=Path)
    parser.add_argument('--field')
    args = parser.parse_args()
    observation = observe(args.directory, args.runner)
    print(observation.get(args.field, '') if args.field else json.dumps(observation))
