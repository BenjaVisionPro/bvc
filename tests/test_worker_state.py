import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('worker_state', Path(__file__).resolve().parents[1] / 'bin/private/workerState.py')
worker_state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker_state)


class WorkerStateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name)
        self.runner = self.directory / 'worker with spaces.topaz'
        (self.directory / 'launch.json').write_text(json.dumps({'pid': 123, 'token': 'current'}))

    def tearDown(self):
        self.tmp.cleanup()

    def observe(self, native, command=None, code=0, error=''):
        (self.directory / 'state.json').write_text(json.dumps(native))
        process = SimpleNamespace(returncode=code, stdout=command or f'topaz -l -S {self.runner}\n', stderr=error)
        with patch.object(worker_state.subprocess, 'run', return_value=process):
            return worker_state.observe(self.directory, self.runner)

    def test_stale_readiness_token_cannot_mark_new_process_ready(self):
        result = self.observe({'pid': 123, 'token': 'previous', 'state': 'running'})
        self.assertEqual(result['state'], 'starting')

    def test_reused_pid_with_another_command_is_not_the_worker(self):
        result = self.observe({'pid': 123, 'token': 'current', 'state': 'running'}, command='unrelated-process')
        self.assertFalse(result['live'])
        self.assertEqual(result['state'], 'exited')

    def test_cleanup_is_not_complete_until_process_exits(self):
        native = {'pid': 123, 'token': 'current', 'state': 'stopped'}
        self.assertEqual(self.observe(native)['state'], 'stopping')
        self.assertEqual(self.observe(native, code=1)['state'], 'stopped')

    def test_unconfirmed_cleanup_survives_process_exit(self):
        result = self.observe({'pid': 123, 'token': 'current', 'state': 'cleanupPending'}, code=1)
        self.assertEqual(result['state'], 'cleanupPending')

    def test_unavailable_process_inspection_is_unknown(self):
        result = self.observe({}, code=1, error='Operation not permitted')
        self.assertEqual(result['state'], 'unknown')
        self.assertIsNone(result['live'])
