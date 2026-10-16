"""CLI contract tests. External runtimes are stubbed; no downloads or real stones.

Run: python3 -m unittest discover -s tests -v
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
MOCK = r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ['BVC_TEST_ROOT'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'events').open('a') as f:
    f.write(json.dumps([name, args]) + '\n')
if os.environ.get('FAIL_COMMAND') == name:
    sys.exit(42)
if name == 'installProject.stone' and os.environ.get('FAIL_PROJECT'):
    if args[0].endswith('/' + os.environ['FAIL_PROJECT'] + '.ston'):
        sys.exit(43)
def option(key):
    return next((a.split('=', 1)[1] for a in args if a.startswith(key + '=')), None)
if name == 'registryReport.solo':
    stone = option('--stone')
    if stone:
        sys.exit(0 if (root / 'registered' / stone).exists() else 1)
    print('#stones : {')
    for p in sorted((root / 'registered').iterdir()):
        print("  '%s' : 'stone'," % p.name)
    print('},')
elif name == 'registerStonesDirectory.solo':
    (root / 'stones-directory').write_text(option('--stonesDirectory'))
elif name == 'createStone.solo':
    stone = args[-2]
    (root / 'registered' / stone).touch()
    d = pathlib.Path((root / 'stones-directory').read_text()) / stone
    d.mkdir(parents=True, exist_ok=True)
    (d / 'gem.conf').touch()
    (d / 'system.conf').touch()
    (d / '.GDKStoneSpec.ston').write_text(
        "GDKStoneSpec { #stoneDirectorySpecName : '%s' }\n" % option('--template'))
elif name == 'gslist.solo':
    for p in sorted((root / 'running').iterdir()):
        print('exists 3.7.5 tester 123 456 Oct 12 10:00 Stone ' + p.name)
elif name == 'startStone.solo':
    stone = next(a for a in args if not a.startswith('-'))
    running = root / 'running' / stone
    if running.exists():
        sys.exit(41)  # Upstream startstone returns nonzero if already running.
    running.touch()
    if any(a.startswith('--wait=') for a in args):
        print("a SmallInteger does not understand #'!='", file=sys.stderr)
        sys.exit(42)  # Reproduce the installed GsDevKit wait-option defect.
elif name == 'stopStone.solo':
    (root / 'running' / args[-1]).unlink()
elif name == 'deleteStone.solo':
    (root / 'running' / args[-1]).unlink(missing_ok=True)
    (root / 'registered' / args[-1]).unlink()
elif name == 'curl':
    if '-fSLo' in args:
        pathlib.Path(args[args.index('-fSLo') + 1]).touch()
    else:
        print('test-gt.zip')
elif name == 'unzip':
    d = pathlib.Path(args[args.index('-d') + 1])
    (d / 'GlamorousToolkit.image').touch()
    if sys.platform == 'darwin':
        cli = d / 'GlamorousToolkit.app/Contents/MacOS/GlamorousToolkit-cli'
    else:
        cli = d / 'bin/GlamorousToolkit-cli'
        cli.parent.mkdir(parents=True, exist_ok=True)
        (cli.parent / 'GlamorousToolkit').touch()
    cli.parent.mkdir(parents=True, exist_ok=True)
    shutil_source = root / 'fake-gt'
    cli.write_bytes(shutil_source.read_bytes())
    cli.chmod(0o755)
'''
FAKE_GT = r'''
import os, pathlib, sys, time
root = pathlib.Path(os.environ['BVC_TEST_ROOT'])
if 'st' in sys.argv:
    script = pathlib.Path(sys.argv[sys.argv.index('st') + 1]).name
    with (root / 'loads').open('a') as f:
        f.write(script + '\n')
    if script == os.environ.get('FAIL_LOAD'):
        sys.exit(37)
    if script == 'preLoad.st':
        (pathlib.Path(sys.argv[1]).parent / (os.environ['GT_APP_NAME'] + '.image')).touch()
else:
    with (root / 'launches').open('a') as f:
        f.write(str(os.getpid()) + '\n')
    if os.environ.get('FAIL_LAUNCH'):
        sys.exit(39)
    time.sleep(120)
'''


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='bvc-test-')
        self.root = Path(self.tmp.name).resolve()
        self.project = self.root / 'My Game'
        self.project.mkdir()
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        (self.root / 'registered').mkdir()
        (self.root / 'running').mkdir()
        (self.root / 'stones-home').mkdir()
        self.write_exe(self.root / 'fake-gt', FAKE_GT)
        commands = ['versionReport.solo', 'registryReport.solo', 'createProjectSet.solo',
                    'registerProjectDirectory.solo', 'cloneProjectsFromProjectSet.solo',
                    'downloadGemStone.solo', 'updateClientLibs.solo', 'registerProduct.solo',
                    'registerStonesDirectory.solo', 'createStone.solo', 'updateCustomEnv.solo',
                    'startStone.solo', 'stopStone.solo', 'startNetldi.solo', 'stopNetldi.solo',
                    'gslist.solo', 'deleteStone.solo',
                    'enableUnicodeCompares.topaz', 'testInstallDevtools', 'testInstallProjects',
                    'installProject.stone',
                    'curl', 'unzip']
        for name in commands:
            self.write_exe(self.tools / name, MOCK)
        self.env = {'PATH': str(self.tools) + os.pathsep + os.environ['PATH'],
                    'HOME': str(self.root), 'TERM': 'dumb', 'NO_COLOR': '1',
                    'BVC_TEST_ROOT': str(self.root), 'STONES_HOME': str(self.root / 'stones-home')}
        self.cli('init')
        installers = self.project / 'config/gemstone/installers'
        installers.mkdir(parents=True)
        (installers / 'dev_tools.install').write_text(
            'install_devtools_projects() { testInstallDevtools "$@"; }\n')
        (installers / 'projects.install').write_text(
            'install_projects() { testInstallProjects "$@"; }\n')

    def tearDown(self):
        launches = self.root / 'launches'
        if launches.exists():
            for pid in launches.read_text().splitlines():
                try:
                    os.kill(int(pid), signal.SIGTERM)
                except ProcessLookupError:
                    pass
        self.tmp.cleanup()

    def write_exe(self, path, body):
        path.write_text('#!' + sys.executable + '\n' + body)
        path.chmod(0o755)

    def cli(self, *args, ok=True, cwd=None, **overrides):
        p = subprocess.run([str(REPO / 'bin/bvc'), *args], cwd=cwd or self.project,
                           env=dict(self.env, **overrides), text=True, capture_output=True,
                           timeout=30)
        if ok:
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        else:
            self.assertNotEqual(p.returncode, 0, p.stdout + p.stderr)
        return p

    def events(self, name=None):
        file = self.root / 'events'
        events = [json.loads(x) for x in file.read_text().splitlines()] if file.exists() else []
        return [e for e in events if name is None or e[0] == name]

    def test_init_creates_named_directory_and_copies_gitignore(self):
        self.cli('init', 'New Game', cwd=self.root)
        project = self.root / 'New Game'
        self.assertTrue((project / '.gitignore').exists())
        self.assertIn('BVC_PROJECT_NAME:=New Game',
                      (project / 'config/bvc/bvc_defaults').read_text())

    def test_init_preserves_existing_project_and_gitignore(self):
        config = self.project / 'config/bvc/bvc_defaults'
        config.write_text(': "${BVC_PROJECT_NAME:=Custom}"\n')
        (self.project / '.gitignore').write_text('keep-me\n')
        self.cli('init')
        self.assertEqual(config.read_text(), ': "${BVC_PROJECT_NAME:=Custom}"\n')
        self.assertEqual((self.project / '.gitignore').read_text(), 'keep-me\n')

    def test_init_preserves_gitignore_when_adding_config(self):
        other = self.root / 'Existing'
        other.mkdir()
        (other / '.gitignore').write_text('keep-me\n')
        self.cli('init', str(other))
        self.assertEqual((other / '.gitignore').read_text(), 'keep-me\n')
        self.assertTrue((other / 'config/bvc/bvc_defaults').exists())

    def test_init_honors_alternate_config_root(self):
        self.cli('init', 'Alternate', cwd=self.root, BVC_CONF_DIR='settings')
        self.assertTrue((self.root / 'Alternate/settings/bvc/bvc_defaults').exists())
        self.assertFalse((self.root / 'Alternate/config').exists())

    def test_unknown_template_creates_nothing(self):
        self.cli('init', 'Missing', '--template=missing', cwd=self.root, ok=False)
        self.assertFalse((self.root / 'Missing').exists())

    def test_help_is_successful_and_has_no_external_side_effects(self):
        for command in ('init', 'build', 'run', 'start', 'stop', 'list', 'delete'):
            self.cli(command, '--help')
        self.assertEqual(self.events(), [])

    def test_removed_commands_and_invalid_arguments_fail(self):
        for args in [('create',), ('devkit',), ('run', 'anything'), ('build', 'anything'),
                     ('build', '--with-seaside'), ('start', 'web', '--with-seaside'),
                     ('stop',), ('start', '../bad'), ('delete', '../bad', '--force')]:
            self.cli(*args, ok=False)
        self.assertEqual(self.events(), [])

    def test_run_builds_app_without_starting_or_installing_stone(self):
        self.cli('run')
        self.assertTrue((self.project / 'devkit/My Game.image').exists())
        self.assertEqual(self.events('createStone.solo'), [])
        self.assertEqual(self.events('startStone.solo'), [])
        self.assertEqual((self.root / 'loads').read_text().splitlines(),
                         ['preLoad.st', 'loadProjects.st', 'postLoad.st'])

    def test_run_twice_reuses_build_and_process(self):
        self.cli('run')
        downloads = len(self.events('curl'))
        self.cli('run')
        self.assertEqual(len((self.root / 'launches').read_text().splitlines()), 1)
        self.assertEqual(len(self.events('curl')), downloads)

    def test_run_existing_app_does_not_require_gemstone(self):
        self.cli('run')
        # The second invocation returns before touching any GemStone tooling.
        before = self.events()
        self.cli('run', STONES_HOME='/nonexistent', FAIL_COMMAND='registryReport.solo')
        self.assertEqual(self.events(), before)

    def test_build_runs_both_and_reuses_existing_deployment(self):
        self.cli('build', GEMSTONE_STONE_NAME='my-production')
        self.assertTrue((self.root / 'registered/my-production').exists())
        self.assertEqual(len(self.events('testInstallProjects')), 1)
        self.assertIn('--template=default_rowan3', self.events('createStone.solo')[0][1])
        self.assertTrue((self.root / 'launches').exists())
        self.cli('build', GEMSTONE_STONE_NAME='my-production')
        self.assertEqual(len(self.events('createStone.solo')), 1)
        self.assertEqual(len(self.events('testInstallProjects')), 1)
        self.assertEqual(len((self.root / 'launches').read_text().splitlines()), 1)

    def test_start_stop_list_are_gemstone_only(self):
        self.cli('start', 'production')
        self.cli('start', 'production')
        listing = self.cli('list')
        self.assertIn('Stone production', listing.stdout)
        self.assertEqual(self.events('gslist.solo')[-1][1], ['-l'])
        self.cli('stop', 'production')
        self.cli('stop', 'production')
        self.cli('list')
        self.assertEqual(len(self.events('createStone.solo')), 1)
        self.assertEqual(len(self.events('stopStone.solo')), 1)
        self.assertEqual(len(self.events('startStone.solo')), 1)
        self.assertFalse((self.root / 'launches').exists())
        self.assertFalse((self.project / 'devkit').exists())

    def test_failed_project_set_does_not_build_or_report_success(self):
        self.cli('run', FAIL_COMMAND='createProjectSet.solo', ok=False)
        self.assertEqual(self.events('cloneProjectsFromProjectSet.solo'), [])
        self.assertEqual(self.events('curl'), [])
        self.assertFalse((self.root / 'launches').exists())
        self.cli('run')  # Retry succeeds; the operation lock was released.

    def test_failed_image_load_is_not_published_and_can_be_retried(self):
        self.cli('run', FAIL_LOAD='loadProjects.st', ok=False)
        self.assertFalse((self.project / 'devkit').exists())
        self.assertEqual(list(self.project.glob('devkit.build.*')), [])
        self.cli('run')
        self.assertTrue((self.project / 'devkit/My Game.image').exists())

    def test_failed_download_does_not_publish_build(self):
        self.cli('run', FAIL_COMMAND='curl', ok=False)
        self.assertFalse((self.project / 'devkit').exists())
        self.assertFalse((self.root / 'launches').exists())

    def test_failed_launch_is_reported_with_log_location(self):
        result = self.cli('run', FAIL_LAUNCH='1', ok=False)
        self.assertIn('bvc.log', result.stderr)
        self.cli('run')

    def test_failed_stone_install_resumes_without_recreating_data(self):
        self.cli('build', FAIL_COMMAND='testInstallProjects', ok=False)
        marker = self.project / 'stones/.bvc_dev.bvc-installing'
        self.assertEqual(marker.read_text().strip(), 'rowan:devtools')
        data = self.project / 'stones/bvc_dev/keep-data'
        data.write_text('existing application data')
        before = len(self.events('startStone.solo'))
        self.cli('build')
        self.assertEqual(len(self.events('startStone.solo')), before)
        self.assertEqual(len(self.events('createStone.solo')), 1)
        self.assertEqual(len(self.events('testInstallDevtools')), 1)
        self.assertEqual(len(self.events('testInstallProjects')), 2)
        self.assertEqual(data.read_text(), 'existing application data')
        self.assertFalse(marker.exists())
        self.assertTrue((self.root / 'launches').exists())

    def use_bundled_installers(self):
        for name in ('dev_tools.install', 'projects.install'):
            (self.project / 'config/gemstone/installers' / name).unlink()

    def installed_projects(self):
        return [Path(args[0]).stem for _, args in self.events('installProject.stone')]

    def test_bundled_installers_use_gsdevkit_without_interactive_debugger(self):
        self.use_bundled_installers()
        self.cli('start', 'production')
        self.assertEqual(self.installed_projects(), [
            'RemoteServiceReplication', 'RowanClientServices', 'Sparkle',
            'gtoolkit-wireencoding', 'gt4gemstone', 'gtoolkit-remote',
            'CatalystFoundation', 'CatalystRuntime', 'CatalystProcess'])
        for _, args in self.events('installProject.stone'):
            self.assertNotIn('-D', args)
            self.assertNotIn('--debug', args)
            self.assertTrue(any(a.startswith('--projectsHome=') for a in args))
        self.assertIn('--alias=RowanClientServicesV3',
                      self.events('installProject.stone')[1][1])

    def test_gt_load_failure_stops_before_catalyst_and_remains_retryable(self):
        self.use_bundled_installers()
        self.cli('start', 'production', FAIL_PROJECT='gtoolkit-wireencoding', ok=False)
        marker = self.project / 'stones/.production.bvc-installing'
        self.assertEqual(marker.read_text().strip(), 'rowan:configured')
        self.assertEqual(self.installed_projects()[-1], 'gtoolkit-wireencoding')
        self.assertNotIn('CatalystFoundation', self.installed_projects())
        self.cli('start', 'production')
        self.assertFalse(marker.exists())
        self.assertEqual(len(self.events('createStone.solo')), 1)
        self.assertEqual(self.installed_projects()[-1], 'CatalystProcess')

    def test_catalyst_failure_stops_and_retry_preserves_completed_devtools(self):
        self.use_bundled_installers()
        self.cli('start', 'production', FAIL_PROJECT='CatalystRuntime', ok=False)
        marker = self.project / 'stones/.production.bvc-installing'
        self.assertEqual(marker.read_text().strip(), 'rowan:devtools')
        self.assertNotIn('CatalystProcess', self.installed_projects())
        self.cli('start', 'production')
        self.assertFalse(marker.exists())
        self.assertEqual(self.installed_projects().count('gt4gemstone'), 1)
        self.assertEqual(self.installed_projects().count('CatalystRuntime'), 2)
        self.assertEqual(len(self.events('createStone.solo')), 1)

    def test_legacy_empty_marker_resumes_after_stone_start(self):
        self.cli('start', 'bvc_dev', FAIL_COMMAND='enableUnicodeCompares.topaz', ok=False)
        marker = self.project / 'stones/.bvc_dev.bvc-installing'
        marker.write_text('')  # State left by the original --wait failure.
        self.cli('build')
        self.assertEqual(len(self.events('createStone.solo')), 1)
        self.assertEqual(len(self.events('startStone.solo')), 1)
        self.assertEqual(len(self.events('testInstallProjects')), 1)
        self.assertFalse(marker.exists())
        conf = (self.project / 'stones/bvc_dev/gem.conf').read_text()
        self.assertLessEqual(conf.count('GEM_NATIVE_CODE_ENABLED=0;'), 1)

    def test_start_avoids_upstream_wait_option(self):
        self.cli('start', 'production')
        args = self.events('startStone.solo')[0][1]
        self.assertFalse(any(a.startswith('--wait') for a in args))

    def test_legacy_seaside_marker_is_not_resumed_as_rowan(self):
        self.cli('start', 'bvc_dev', FAIL_COMMAND='enableUnicodeCompares.topaz', ok=False)
        (self.project / 'stones/.bvc_dev.bvc-installing').write_text('')
        (self.project / 'stones/bvc_dev/.GDKStoneSpec.ston').write_text(
            "GDKStoneSpec { #stoneDirectorySpecName : 'default_seaside' }\n")
        self.cli('start', 'bvc_dev', ok=False)
        self.assertEqual(self.events('testInstallProjects'), [])
        self.assertEqual(len(self.events('createStone.solo')), 1)

    def test_unsupported_installation_marker_preserves_stone(self):
        self.cli('start', 'bvc_dev', FAIL_COMMAND='enableUnicodeCompares.topaz', ok=False)
        marker = self.project / 'stones/.bvc_dev.bvc-installing'
        data = self.project / 'stones/bvc_dev/user-data'
        data.write_text('preserve')
        before = [e for e in self.events() if e[0] != 'registryReport.solo']
        for phase in ('seaside', 'seaside:projects'):
            with self.subTest(phase=phase):
                marker.write_text(phase)
                result = self.cli('start', 'bvc_dev', ok=False)
                self.assertIn('Only Rowan installations can be resumed', result.stderr)
                self.assertEqual(marker.read_text(), phase)
                self.assertEqual(data.read_text(), 'preserve')
                self.assertEqual(
                    [e for e in self.events() if e[0] != 'registryReport.solo'], before)

    def test_interrupted_stone_creation_is_not_overwritten(self):
        self.cli('start', 'bvc_dev', FAIL_COMMAND='enableUnicodeCompares.topaz', ok=False)
        (self.project / 'stones/.bvc_dev.bvc-installing').write_text('rowan:creating\n')
        self.cli('start', 'bvc_dev', ok=False)
        self.assertEqual(len(self.events('createStone.solo')), 1)

    def test_incomplete_existing_image_is_preserved(self):
        devkit = self.project / 'devkit'
        devkit.mkdir()
        image = devkit / 'My Game.image'
        image.write_text('live-work')
        self.cli('run', ok=False)
        self.assertEqual(image.read_text(), 'live-work')

    def test_pharo_download_failure_propagates(self):
        p = subprocess.run([str(REPO / 'bin/bvcBuildPharoRuntime.sh')], cwd=self.project,
                           env=dict(self.env, FAIL_COMMAND='curl'), capture_output=True,
                           text=True, timeout=30)
        self.assertNotEqual(p.returncode, 0)
        self.assertNotIn('Pharo build complete', p.stderr)

    def test_run_with_trailing_slash_install_dir(self):
        self.cli('run', GT_INSTALL_DIR='custom-devkit/')
        self.cli('run', GT_INSTALL_DIR='custom-devkit/')
        self.assertEqual(len((self.root / 'launches').read_text().splitlines()), 1)

    def test_launch_lock_prevents_duplicate_work(self):
        lock = self.project / 'devkit.run-lock'
        lock.mkdir()
        (lock / 'pid').write_text(str(os.getpid()))
        self.cli('run', ok=False)
        self.assertEqual(self.events(), [])
        self.assertTrue(lock.exists())

    def test_clone_failure_propagates(self):
        self.cli('run', FAIL_COMMAND='cloneProjectsFromProjectSet.solo', ok=False)
        self.assertEqual(self.events('curl'), [])

    def test_existing_stone_start_failure_stops_full_build(self):
        (self.root / 'registered/bvc_dev').touch()
        self.cli('build', FAIL_COMMAND='startStone.solo', ok=False)
        self.assertFalse((self.root / 'launches').exists())

    def test_bootstrap_environment_is_available_in_same_process(self):
        scripts = self.root / 'bootstrap/bin'
        scripts.mkdir(parents=True)
        setup = scripts / 'setupGsDevKit_stones.sh'
        setup.write_text('''#!/bin/bash
set -eu
mkdir -p "$STONES_HOME/git/GsDevKit_stones/bin"
printf '#!/bin/sh\\nexit 0\\n' > "$STONES_HOME/git/GsDevKit_stones/bin/versionReport.solo"
chmod +x "$STONES_HOME/git/GsDevKit_stones/bin/versionReport.solo"
''')
        setup.chmod(0o755)
        home = self.root / 'new-gsdevkit'
        p = subprocess.run(['/bin/bash', '-c',
                            'SCRIPT_DIR="$1"; . "$2"; ensure_gsdevkit_ready; '
                            'command -v versionReport.solo; printf "%s" "$STONES_DATA_HOME"',
                            'test-bootstrap', str(scripts), str(REPO / 'bin/private/shFunctions')],
                           cwd=self.project,
                           env=dict(self.env, PATH='/usr/bin:/bin', STONES_HOME=str(home)),
                           text=True, capture_output=True, timeout=10)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn(str(home / 'git/GsDevKit_stones/bin/versionReport.solo'), p.stdout)
        self.assertIn(str(home / 'data'), p.stdout)


if __name__ == '__main__':
    unittest.main()
