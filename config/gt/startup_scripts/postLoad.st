[
	| registry connector |
	
	5 seconds wait.
	BVCDevKit initializeKnowledgeBase.		
	5 seconds wait.
	BVCDevKitWorld openDefault. 
	5 seconds wait.
	
"
	(registry := GtGemStoneSessionRegistry default)
	availableConnectors do: [ :connector | 
		registry removeConnector: connector
	].
	registry resetSessions; resetConnectors.
	connector := registry propertiesFile addNewConnector.
	connector
		name: 'bvc_dev';
		host: 'localhost';
		libraryPath: '/opt/GsDevKit/gemstone/clientlibs' asFileReference;
		gemstoneVersion: '3.7.5';
		stone: 'bvc_dev';
		netldi: 'bvc_dev_ldi';
		username: 'DataCurator';
		password: 'swordfish'.
	connector
		notifyNameChanged;
		notifyUpdated.
	registry propertiesFile saveProperties.
"

	5 seconds wait
] on: Error do: [ :e | 
	Smalltalk logError: e messageText inContext: e signalerContext. 
	Smalltalk exitFailure 
]. 
Smalltalk garbageCollect; garbageCollect; garbageCollect.
5 seconds wait.
