1 second wait.
GtWorld allInstances first removeShutdownListener.
BlParallelUniverse all do: [ :universe | 
	universe spaces ifNotEmpty: [ 
		universe spaces do: [ :space | universe closeSpaceSynchronously: space].
	].
].
Smalltalk garbageCollect; garbageCollect; garbageCollect.
SmalltalkImage current saveAs: 'BVCDevKit'.