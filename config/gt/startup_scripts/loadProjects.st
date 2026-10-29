| projectsRoot connector |

projectsRoot := 'gitlocal://', (OSPlatform current environment at: 'PROJECTS_ROOT').

"Load projects"
Transcript show: 'LOADING User Projects FROM ', 
	(projectsRoot ifNil: ['<none>']).

"Keep the Futures code and existing instances from the GT release together.
Loading a newer Futures over that image can leave AsyncMutex instances with
locks that its new methods no longer support. Register explicit locks because
the GT release need not register its bundled projects in Metacello."
Metacello new baseline: 'FuturesCore'; lock.
Metacello new baseline: 'Futures'; lock.

Metacello new
        baseline: 'SpartaSkia';
        repository: 'tonel:///opt/git/JupiterJones/gt-blur-workspace/sparta/src';
    	onConflictUseIncoming;
        load.
Metacello new
        baseline: 'Bloc';
        repository: 'tonel:///opt/git/JupiterJones/gt-blur-workspace/Bloc/src';
    	onConflictUseLoaded;
        load.


Metacello new
	repository: 'github://svenvc/NeoCSV/repository';
	baseline: 'NeoCSV';
	load.

Metacello new
	repository: 'github://svenvc/NeoJSON/repository';
	baseline: 'NeoJSON';
	load.

Metacello new
	repository: projectsRoot, '/Gt4FontAwesome/src';
	baseline: 'Gt4FontAwesome';
	onConflictUseLoaded;
	load.
	
(Smalltalk at: #FontAwesomeMetadataImporter)
	importFromIconsJsonFile: '/Users/jupiter/Downloads/fontawesome-pro-plus-7.3.1-desktop/metadata/icons.json'
			asFileReference
	packageName: 'BVC-FontAwesome-Fonts'
	version: '7.3.1'.

Metacello new
	repository: projectsRoot, '/CatalystTheme/src';
	baseline: 'CatalystTheme';
	load.

Metacello new
	repository: projectsRoot, '/CatalystDevKit/src';
	baseline: 'CatalystDevKit';
	onConflictUseLoaded;
	load.

Metacello new
	repository: projectsRoot, '/CatalystFoundation/src';
	baseline: 'CatalystPhysics';
	onConflictUseLoaded;
	load.

Metacello new
	repository: projectsRoot, '/CatalystFoundation/src';
	baseline: 'CatalystFoundation';
	onConflictUseLoaded;
	load.

"Portable simulation kernel and its GT/GemStone conformance models.
Core has no Runtime or ecosystem dependency; tests are development-only."
Metacello new
	repository: projectsRoot, '/catalyst-simulator/src';
	baseline: 'CatalystSimulator';
	onConflictUseLoaded;
	load: #('Tests').

Metacello new
	repository: projectsRoot, '/CatalystRuntime/src';
	baseline: 'CatalystRuntime';
	load.

"Users Runtime service and portable examples share the installed Runtime backend."
Metacello new
	repository: projectsRoot, '/catalyst-users/src';
	baseline: 'CatalystUsers';
	onConflictUseLoaded;
	load: #('tests').

Metacello new
	repository: projectsRoot, '/CatalystConnect/src';
	baseline: 'CatalystConnect';
	onConflictUseLoaded;
	load: #('reference' 'tests').

Metacello new
	repository: projectsRoot, '/CatalystProcess/src';
	baseline: 'CatalystProcess';
	onConflictUseLoaded;
	load.

"Groups development core, Runtime integration, GT views, tests and examples.
This GT-only load does not add Groups to the GemStone installer."
Metacello new
	repository: projectsRoot, '/catalyst-groups/src';
	baseline: 'CatalystGroups';
	onConflictUseLoaded;
	load: #('Development').

2 seconds wait
