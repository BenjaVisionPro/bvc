#!/usr/bin/env python3
"""Opt-in integration test against an existing, provisioned development stone.

The configuration must deploy runtimeOrchestrator and a socket-free probe service
to separate logical hosts. The test removes only its uniquely named Runtimes.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--configuration', type=Path, required=True)
    parser.add_argument('--deployment', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    bvc = Path(__file__).resolve().parents[1] / 'bin/bvc'
    name = 'bvc_lifecycle_' + uuid.uuid4().hex[:12]
    env = dict(os.environ, GEMSTONE_STONE_NAME=args.deployment)
    evidence = {'stone': args.deployment, 'runtime': name, 'checks': {}}

    def command(action, runtime=name, configuration=None, success=True):
        argv = [str(bvc), 'runtime', action, runtime]
        if configuration is not None:
            argv.append(str(configuration))
        result = subprocess.run(argv, cwd=args.project, env=env, text=True,
                                capture_output=True, timeout=90)
        if not success:
            assert result.returncode != 0, result.stdout
            return result
        assert result.returncode == 0, result.stdout + result.stderr
        return json.loads(result.stdout)

    def settled(version):
        deadline = time.monotonic() + 45
        while True:
            result = command('status')
            if result['state'] == 'running' and result['configurationVersion'] == version:
                return result
            assert time.monotonic() < deadline, result
            time.sleep(.15)

    def active(report):
        return {w['workerIdentifier']: w['process']['pid'] for w in report['workers']
                if w['process']['live']}

    def topaz(code):
        with tempfile.TemporaryDirectory(prefix='bvc-native-check-') as directory:
            script = Path(directory) / 'check.topaz'
            output = Path(directory) / 'result.json'
            script.write_text('run\nSystem abortTransaction. System transactionMode: #manualBegin. true\n%\nrun\n'
                              + code.replace('@CHECK_DIRECTORY@', directory) + "\n%\nrun\n| file |\nfile := GsFile openWriteOnServer: '"
                              + str(output) + "'. [file nextPutAll: '{}'] ensure: [file close]. true\n%\n")
            result = subprocess.run([str(bvc), 'topaz', args.deployment, '--script', str(script)],
                                    cwd=args.project, env=env, text=True, capture_output=True, timeout=60)
            assert result.returncode == 0 and output.exists(), result.stdout + result.stderr

    def passed(check):
        evidence['checks'][check] = True
        print(check, flush=True)

    command('start', success=False)
    command('status', success=False)
    passed('unknownRuntimeRequiresConfiguration')
    configured = command('configure', configuration=args.configuration.resolve())
    assert configured['state'] == 'stopped' and configured['workers'] == []
    assert configured['configurationVersion'] == 1
    assert command('status')['runtimeIdentifier'] == configured['runtimeIdentifier']
    passed('configurePersistsWithoutStarting')
    command('start')
    running = settled(1)
    assert len(active(running)) == 2, running
    assert len({w['hostIdentifier'] for w in running['workers'] if w['process']['live']}) == 2
    assert all(s['appliedConfigurationVersion'] == 1 for w in running['workers']
               if w['process']['live'] for s in w['services'])
    evidence['firstActivation'] = running
    passed('crossGemServicePublicationAndVersionAdoption')
    assert active(command('start')) == active(running)
    passed('repeatedStartReusesGems')
    command('remove', success=False)
    passed('runningRuntimeCannotBeRemoved')
    with tempfile.TemporaryDirectory(prefix='bvc-config-rejection-') as directory:
        invalid = Path(directory) / 'invalid.ston'
        invalid.write_text(args.configuration.read_text().replace('#maxProcesses : 4', '#maxProcesses : -1'))
        assert invalid.read_text() != args.configuration.read_text()
        command('configure', configuration=invalid, success=False)
        assert command('status')['configurationVersion'] == 1
        command('configure', runtime=name + '_invalid', configuration=invalid, success=False)
        command('status', runtime=name + '_invalid', success=False)
    passed('rejectedConfigurationPreservesVersionAndRegistry')
    command('configure', configuration=args.configuration.resolve())
    reconfigured = settled(2)
    assert active(reconfigured) == active(running)
    passed('runningConfigurationAdoptedWithoutReplacingGems')
    root = "#'" + name + "_evidence'"
    topaz(f"CRGemStoneRuntime duringTransaction: [(UserGlobals includesKey: {root}) ifTrue: [self error: 'Qualification root already exists']. "
          f"UserGlobals at: {root} put: (CRRuntimeRegistry default runtimeNamed: '{name}') nativeAuthority]. true")
    stopped = command('stop')
    assert stopped['state'] == 'stopped' and not active(stopped)
    assert command('stop')['state'] == 'stopped'
    assert stopped['configurationVersion'] == 2
    passed('gracefulStopAndRepeatedStop')
    command('restart')
    restarted = settled(2)
    assert not (set(active(restarted).values()) & set(active(running).values()))
    assert restarted['runtimeIdentifier'] == configured['runtimeIdentifier']
    passed('restartRetainsRuntimeIdentityAndAcceptedVersion')
    topaz(f"""| runtime host rejected revision staleAuthority staleVersion valid deadline oldConfiguration |
runtime := CRRuntimeRegistry default runtimeNamed: '{name}'.
(runtime activation isCurrentOrchestrationAuthority: (UserGlobals at: {root})) ifTrue: [self error: 'Old owner still has authority'].
host := runtime nativeHosts values detect: [:each | (runtime publications at: each workerIdentifier ifAbsent: [CRWorkerHandle new]) lifecycleStatus = CRStatus running].
revision := runtime nativeRevision. rejected := false.
[runtime publish: CRWorkerHandle new from: host token: 'obsolete'] on: Error do: [:error | rejected := true].
rejected ifFalse: [self error: 'Stale publisher was accepted'].
runtime nativeRevision = revision ifFalse: [self error: 'Stale publisher changed topology'].
rejected := false.
[(CRGemStoneRemoteWorkQueue new descriptor: runtime workerIdentifier: host workerIdentifier generation: 'obsolete') enqueue: CRWorkUnit new asEnvelope] on: Error do: [:error | rejected := true].
rejected ifFalse: [self error: 'Stale command proxy was accepted'].
runtime publications valuesDo: [:publication |
 (publication isKindOf: CRWorkerHandle) ifTrue: [
 (publication workQueue isNil and: [publication originalHandle == publication]) ifFalse: [self error: 'Topology retained an operational handle'].
 publication serviceHandles do: [:service | service originalHandle == service ifFalse: [self error: 'Topology retained a live service handle']]]].
staleAuthority := (CRGemStoneLifecycleSentinelWork new outputPath: '@CHECK_DIRECTORY@/stale-authority'; yourself) asEnvelope.
staleAuthority context add: (CROrchestrationAuthorityContext new authority: (UserGlobals at: {root}); yourself).
oldConfiguration := runtime configuration. oldConfiguration version: 1.
staleVersion := CRDeploymentVersionContext stamp: (CRGemStoneLifecycleSentinelWork new outputPath: '@CHECK_DIRECTORY@/stale-version'; yourself) asEnvelope configuration: oldConfiguration.
valid := (CRGemStoneLifecycleSentinelWork new outputPath: '@CHECK_DIRECTORY@/valid'; yourself) asEnvelope.
CRGemStoneRuntime duringTransaction: [host controlQueue enqueue: staleAuthority; enqueue: staleVersion; enqueue: valid].
deadline := CRPlatform current currentMillis + 10000.
[(GsFile existsOnServer: '@CHECK_DIRECTORY@/valid') or: [CRPlatform current currentMillis >= deadline]] whileFalse: [Delay waitForMilliseconds: 25].
(GsFile existsOnServer: '@CHECK_DIRECTORY@/valid') ifFalse: [self error: 'Valid control command did not execute'].
((GsFile existsOnServer: '@CHECK_DIRECTORY@/stale-authority') or: [GsFile existsOnServer: '@CHECK_DIRECTORY@/stale-version']) ifTrue: [self error: 'Worker executed an obsolete control command'].
CRGemStoneRuntime duringTransaction: [UserGlobals removeKey: {root}]. true""")
    passed('staleAuthorityPublicationAndSubmissionRejected')
    passed('obsoleteAuthorityAndVersionRejectedAtConsumption')
    passed('publishedTopologyContainsNoOperationalHandles')
    command('restart')
    settled(2)
    passed('restartWhileRunning')
    command('stop')
    assert command('remove')['state'] == 'removed'
    command('status', success=False)
    passed('removeUnregistersStoppedRuntime')
    concurrent_name = name + '_concurrent'
    def configure_concurrently(_):
        return subprocess.run([str(bvc), 'runtime', 'configure', concurrent_name,
                               str(args.configuration.resolve())], cwd=args.project,
                              env=env, text=True, capture_output=True, timeout=90)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        attempts = list(pool.map(configure_concurrently, range(2)))
    assert any(result.returncode == 0 for result in attempts)
    topaz(f"((CRRuntimeRegistry default runtimes select: [:runtime | runtime label = '{concurrent_name}']) size = 1) ifFalse: [self error: 'Duplicate named Runtime']. true")
    command('remove', runtime=concurrent_name)
    passed('concurrentNamedCreationIsUnique')
    evidence['finalState'] = 'removed'
    args.report.write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
