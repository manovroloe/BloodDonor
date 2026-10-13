"""Setup/start contracts without installing packages or starting a real server."""
from contextlib import redirect_stderr, redirect_stdout
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from unittest.mock import patch
import io
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

def load_script(name):
    spec = spec_from_file_location('bloodcare_test_' + name, ROOT / 'scripts' / (name + '.py'))
    module = module_from_spec(spec)
    if name == 'environment':
        spec.loader.exec_module(module)
    else:
        with patch.dict(sys.modules, {'environment': load_script('environment')}):
            spec.loader.exec_module(module)
    return module

class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.venv = self.root / '.venv'
        self.venv.mkdir()
        self.python = self.venv / 'python'
        self.python.touch()
        self.stamp = self.venv / '.bloodcare-setup.json'
        self.stamp.write_text(json.dumps({'requirements_sha256': 'same-lock'}))
        (self.root / '.env').write_text('PRIVATE=test-only-value\n')
        (self.root / '.env.example').write_text('SUPABASE_URL=\n')
        self.module = load_script('setup')

    def run_setup(self, args=(), return_code=0):
        with patch.multiple(self.module, ROOT=self.root, VENV=self.venv, PYTHON=self.python, STAMP=self.stamp), patch.object(self.module, 'supported_python', return_value=True), patch.object(self.module, 'lock_hash', return_value='same-lock'), patch.object(self.module.subprocess, 'run', return_value=subprocess.CompletedProcess([], return_code)) as calls, patch.object(sys, 'argv', ['setup.py', *args]), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            result = self.module.main()
        return result, [call.args[0] for call in calls.call_args_list]

    def test_unchanged_setup_does_not_install_and_keeps_private_config(self):
        result, calls = self.run_setup()
        self.assertEqual(result, 0)
        self.assertEqual(len(calls), 1)
        self.assertNotIn('pip', calls[0])
        self.assertEqual((self.root / '.env').read_text(), 'PRIVATE=test-only-value\n')

    def test_refresh_explicitly_installs_locked_set(self):
        result, calls = self.run_setup(['--refresh'])
        self.assertEqual(result, 0)
        installs = [call for call in calls if 'install' in call]
        self.assertEqual(len(installs), 1)
        self.assertIn('--no-deps', installs[0])
        self.assertEqual(installs[0][-1], str(self.root / 'requirements.txt'))
        self.assertEqual((self.root / '.env').read_text(), 'PRIVATE=test-only-value\n')

    def test_first_configuration_copies_template_only_when_missing(self):
        (self.root / '.env').unlink()
        result, calls = self.run_setup()
        self.assertEqual(result, 0)
        self.assertEqual((self.root / '.env').read_text(), 'SUPABASE_URL=\n')
        self.assertFalse(any('pip' in call for call in calls))

    def test_foreign_or_incomplete_environment_is_not_silently_reused(self):
        self.python.unlink()
        result, calls = self.run_setup()
        self.assertEqual(result, 1)
        self.assertEqual(calls, [])

    def test_normal_start_uses_current_interpreter_without_installation(self):
        module = load_script('start')
        with patch.object(module, 'ROOT', self.root), patch.object(module, 'supported_python', return_value=True), patch.object(module, 'dependency_problems', return_value=[]), patch.object(module.os, 'chdir') as change_dir, patch.object(module.os, 'execv') as execute:
            self.assertEqual(module.main(), 0)
        change_dir.assert_called_once_with(self.root)
        execute.assert_called_once_with(sys.executable, [sys.executable, str(self.root / 'run.py')])

    def test_missing_dependencies_do_not_trigger_install_on_start(self):
        module = load_script('start')
        with patch.object(module, 'supported_python', return_value=True), patch.object(module, 'dependency_problems', return_value=['missing-test-package']), patch.object(module.os, 'execv') as execute, redirect_stderr(io.StringIO()):
            self.assertEqual(module.main(), 1)
        execute.assert_not_called()
