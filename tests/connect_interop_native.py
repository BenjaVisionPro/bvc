#!/usr/bin/env python3
"""Opt-in Quinn interoperability with an existing rebuilt GT and native stone.

Requires the committed Connect tests/helpers already loaded in GT, a native
Connect library and identity tool, and Foundation/Runtime/Connect in the stone.
Creates new private localhost identities in a fresh output directory. Never
edits Smalltalk source or restarts the MCP server. No sockets leave loopback.
"""
import argparse
import json
import os
import re
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.request
import uuid


class Interop:
    def __init__(self, args):
        self.args = args
        self.output = args.output.resolve()
        self.output.mkdir(parents=True, exist_ok=False)
        self.project = args.project.resolve()
        self.library = args.library.resolve()
        self.connect = args.connect.resolve()
        self.bvc = Path(__file__).resolve().parents[1] / 'bin/bvc'
        self.fixture = Path(__file__).resolve().parent / 'fixtures/connect-interop.topaz'
        self.env = dict(os.environ, GEMSTONE_STONE_NAME=args.deployment)
        self.runtime = args.runtime_name or 'connect_interop_' + uuid.uuid4().hex[:12]
        self.rpc_id = 0
        self.evidence = dict(stone=args.deployment, runtime=self.runtime, cases={})

    def write_json(self, file, value):
        file.write_text(json.dumps(value, indent=2) + '\n')

    def rpc(self, code, directory, label):
        self.rpc_id += 1
        request = dict(jsonrpc='2.0', id=self.rpc_id, method='tools/call',
                       params=dict(name='smalltalkCodeEvaluation', arguments=dict(code=code)))
        self.write_json(directory / (label + '-request.json'), request)
        response = json.loads(urllib.request.urlopen(urllib.request.Request(
            self.args.mcp_url, json.dumps(request).encode(),
            {'Content-Type': 'application/json'}), timeout=60).read())
        self.write_json(directory / (label + '-response.json'), response)
        if response.get('error') or response.get('result', {}).get('isError'):
            raise RuntimeError('MCP request failed; original response retained in ' + str(directory))
        for block in response.get('result', {}).get('content', []):
            if block.get('type') != 'text':
                continue
            try:
                result = json.loads(block['text'])
            except ValueError:
                continue
            if isinstance(result, dict) and 'errorDetails' in result:
                raise RuntimeError(result['errorDetails'].get('errorMessage', 'MCP evaluation failed'))
        return response

    @staticmethod
    def st(value):
        return "'" + str(value).replace("'", "''") + "'"

    @staticmethod
    def port():
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.bind(('127.0.0.1', 0))
            return probe.getsockname()[1]

    def options(self, role, local, peer, port):
        identities = self.output / 'identities'
        return dict(role=role, bind='127.0.0.1:' + str(port if role == 'server' else 0),
                    peer='127.0.0.1:' + str(port) if role == 'client' else None,
                    server_name='localhost', certificate=str(identities / local / 'certificate.der'),
                    private_key=str(identities / local / 'private-key.der'),
                    trusted_certificate=str(identities / peer / 'certificate.der'), capacity=4)

    def prepare_case(self, name, gt_role, port):
        directory = self.output / name
        directory.mkdir()
        self.write_json(directory / 'gt-options.json', self.options(gt_role, 'gt', 'gs', port))
        gs_role = 'server' if gt_role == 'client' else 'client'
        self.write_json(directory / 'gs-options.json', self.options(gs_role, 'gs', 'gt', port))
        return directory, gs_role

    def start_gt(self, role, directory):
        q = self.st
        global_name = 'CCInteropRun' + uuid.uuid4().hex
        self.write_json(directory / 'owner.json', dict(globalName=global_name))
        code = f'''| run |
run := CCNativeInteropRun new start: [ | lease cfg example |
 lease := CCNativeMcpLease forRunningServers.
 [lease during: [
 cfg := CCQuicConfiguration new identifier: #connect; label: 'Fresh stone interoperability';
 nativeOptionsJson: {q(directory / 'gt-options.json')} asFileReference contents;
 libraryPath: {q(self.library)}; allowedOperations: #(1 2); principal: 'gs'; yourself.
 example := CCQuicNativeExamples new.
 [example runRole: {q(role)} configuration: cfg directory: {q(directory)}]
 on: Error, TestFailure do: [:error | ({q(directory / 'gt-error.json')}) asFileReference writeStreamDo: [:stream |
 stream nextPutAll: (STONJSON toString: (Dictionary new at: 'error' put: error messageText asString; at: 'class' put: error class name; yourself))]].
 example evidence
 ]] ensure: [({q(directory / 'gt-mcp-gate.json')}) asFileReference writeStreamDo: [:stream | stream nextPutAll: (STONJSON toString: lease snapshot)]]].
Smalltalk globals at: {q(global_name)} asSymbol put: run. run snapshot'''
        self.rpc(code, directory, 'dispatch')

    def start_gs(self, role, directory):
        env = dict(self.env, BVC_CONNECT_INTEROP_DIRECTORY=str(directory),
                   BVC_CONNECT_INTEROP_ROLE=role, BVC_CONNECT_INTEROP_LIBRARY=str(self.library))
        with (directory / 'topaz.log').open('w') as stream:
            return subprocess.Popen([str(self.bvc), 'topaz', self.args.deployment,
                                     '--script', str(self.fixture)], cwd=self.project,
                                    env=env, stdout=stream, stderr=subprocess.STDOUT)

    def wait_json(self, file, process=None, timeout=40):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if file.exists():
                try:
                    return json.loads(file.read_text())
                except ValueError:
                    pass  # The owning process is still writing its result.
            if process is not None and process.poll() is not None:
                raise RuntimeError('Topaz exited before ' + str(file) + '; inspect its log')
            time.sleep(.1)
        raise TimeoutError('Owner still retains resources; no reset/kill attempted: ' + str(file))

    def finish_gt(self, directory):
        # The controller waits on disk OUTSIDE GT before joining or inspecting.
        gate = self.wait_json(directory / 'gt-mcp-gate.json')
        assert gate['state'] == 'released' and gate['originalRegistriesRestored'], gate
        name = json.loads((directory / 'owner.json').read_text())['globalName']
        key = self.st(name) + ' asSymbol'
        self.rpc(f'| run snapshot | run := Smalltalk globals at: {key}. '
                 f'run waitForMillis: 1000. snapshot := run snapshot. '
                 f'Smalltalk globals removeKey: {key}. snapshot', directory, 'join')
        if (directory / 'gt-error.json').exists():
            raise RuntimeError((directory / 'gt-error.json').read_text())
        return self.wait_json(directory / 'gt-evidence.json')

    @staticmethod
    def assert_owner(report, client):
        assert report['workerStopped'] and report['queueEmpty'], report
        assert not report['failures'], report
        service = report['service']
        assert service['buffersReleased'] and not service['stopping'], report
        stats = service['statistics']
        assert stats['copyPeak'] <= 4096 and stats['callPeak'] <= 32 and stats['pendingPeak'] <= 4, stats
        if client:
            assert report['replies'] == 10, report
        else:
            assert stats['published'] == 10, report

    def local_case(self, name, gt_role):
        directory, gs_role = self.prepare_case(name, gt_role, self.port())
        process = None
        dispatched = False
        try:
            if gt_role == 'client':
                process = self.start_gs(gs_role, directory)
                self.wait_json(directory / 'gs-ready.json', process)
                self.start_gt(gt_role, directory)
                dispatched = True
                gt = self.finish_gt(directory)
                (directory / 'stop').touch()
            else:
                self.start_gt(gt_role, directory)
                dispatched = True
                self.wait_json(directory / 'gt-ready.json')
                process = self.start_gs(gs_role, directory)
                assert process.wait(timeout=35) == 0, 'Inspect Topaz log'
                (directory / 'stop').touch()
                gt = self.finish_gt(directory)
            assert process.wait(timeout=15) == 0, 'Inspect Topaz log'
            gs = self.wait_json(directory / 'gs-evidence.json')
            assert gt['pid'] != gs['pid'], 'Interoperability must cross process boundaries'
            self.assert_owner(gt, gt_role == 'client')
            self.assert_owner(gs, gs_role == 'client')
            self.evidence['cases'][name] = dict(gt=gt, gemstone=gs)
            print(name + ': passed', flush=True)
        finally:
            (directory / 'stop').touch()
            if process is not None and process.poll() is None:
                # Graceful fixture stop; never kill a Gem or discard its evidence.
                process.wait(timeout=40)
            if dispatched and not (directory / 'join-response.json').exists():
                self.finish_gt(directory)

    def runtime_command(self, action, configuration=None, allow_missing=False):
        argv = [str(self.bvc), 'runtime', action, self.runtime]
        if configuration is not None:
            argv.append(str(configuration))
        result = subprocess.run(argv, cwd=self.project, env=self.env, text=True,
                                capture_output=True, timeout=90)
        log = self.output / ('runtime-' + str(time.monotonic_ns()) + '.log')
        log.write_text(result.stdout + result.stderr)
        if allow_missing and result.returncode:
            # Only a confirmed unknown name permits creating a new test Runtime.
            assert re.search(r'^ERROR[^\n]*No Runtime is registered with this name[^\n]*$',
                             result.stderr + result.stdout, re.MULTILINE), log
            return None
        assert result.returncode == 0, 'Inspect ' + str(log)
        return json.loads(result.stdout)

    def settled(self):
        deadline = time.monotonic() + 45
        while True:
            status = self.runtime_command('status')
            if status['state'] == 'running':
                return status
            assert time.monotonic() < deadline, status
            time.sleep(.15)

    def managed_client(self, name, port):
        directory, _ = self.prepare_case(name, 'client', port)
        self.start_gt('client', directory)
        report = self.finish_gt(directory)
        self.assert_owner(report, True)
        self.evidence['cases'][name] = report
        print(name + ': passed', flush=True)

    def managed_case(self):
        assert self.runtime_command('status', allow_missing=True) is None, 'Runtime already exists'
        configuration = self.output / 'runtime.ston'
        port = self.port()
        identities = self.output / 'identities'
        subprocess.run([sys.executable, str(self.connect / 'scripts/runtime-configuration.py'),
                        '--library', str(self.library), '--identity', str(identities / 'gs'),
                        '--trusted-certificate', str(identities / 'gt/certificate.der'),
                        '--principal', 'gt', '--operations', '1', '2', '--capacity', '4',
                        '--bind', '127.0.0.1:' + str(port), '--output', str(configuration)], check=True)
        configured = self.runtime_command('configure', configuration)
        assert configured['state'] == 'stopped' and configured['workers'] == [], configured
        self.evidence['configured'] = configured
        success = False
        try:
            self.runtime_command('start')
            first = self.settled()
            self.evidence['firstActivation'] = first
            self.managed_client('gt-client-managed-server', port)
            self.runtime_command('restart')
            second = self.settled()
            self.evidence['secondActivation'] = second
            first_pids = {w['process']['pid'] for w in first['workers'] if w['process']['live']}
            second_pids = {w['process']['pid'] for w in second['workers'] if w['process']['live']}
            assert first_pids.isdisjoint(second_pids), (first, second)
            assert first['runtimeIdentifier'] == second['runtimeIdentifier']
            assert first['configurationVersion'] == second['configurationVersion']
            self.managed_client('gt-client-restarted-server', port)
            success = True
        finally:
            if success and self.args.keep_runtime:
                self.evidence['leftRunning'] = self.runtime_command('status')
                self.evidence['serverAddress'] = '127.0.0.1:' + str(port)
            else:
                self.evidence['stopped'] = self.runtime_command('stop')
                self.evidence['removed'] = self.runtime_command('remove')

    def preflight(self):
        q = self.st
        code = f"""| report names |
names := #(CCQuicService CCQuicNativeExamples CCNativeMcpLease CCNativeInteropRun).
report := Dictionary new at: 'image' put: Smalltalk image imageFile fullName;
 at: 'pid' put: GtOsSystemInfo current currentProcessId;
 at: 'classes' put: (names collect: [:name | {{name. Smalltalk globals includesKey: name}}]);
 at: 'library' put: CCPharoQuicNative loadedPath; yourself.
({q(self.output / 'gt-preflight.json')}) asFileReference writeStreamDo: [:stream | stream nextPutAll: (STONJSON toString: report)]. true"""
        self.rpc(code, self.output, 'preflight')
        report = self.wait_json(self.output / 'gt-preflight.json')
        assert all(loaded for _, loaded in report['classes']), 'Load Connect tests/helpers in GT first'
        assert report['library'] in (None, str(self.library)), 'Use GT existing immutable library binding'
        self.evidence['gt'] = report

    def run(self):
        try:
            self.preflight()
            identity = self.library.parent / 'identity'
            for peer in ('gt', 'gs'):
                subprocess.run([str(identity), str(self.output / 'identities' / peer)], check=True)
            self.local_case('gt-client-gemstone-server', 'client')
            self.local_case('gemstone-client-gt-server', 'server')
            self.managed_case()
            self.evidence['status'] = 'passed'
        except Exception as error:
            self.evidence['status'] = 'failed'
            self.evidence['error'] = str(error)
            raise
        finally:
            self.write_json(self.output / 'interop-evidence.json', self.evidence)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--deployment', required=True)
    parser.add_argument('--connect', type=Path, required=True)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mcp-url', default='http://127.0.0.1:3001/')
    parser.add_argument('--runtime-name')
    parser.add_argument('--keep-runtime', action='store_true')
    Interop(parser.parse_args()).run()


if __name__ == '__main__':
    main()
