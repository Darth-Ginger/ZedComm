# ZedComm trigger probes

Install this folder as a local mod alongside ZedComm in a disposable debug save. Enable ZedComm Trigger Probes.

Place a test button or tripwire with the Lua console:

~~~lua
button = ZedCommTriggerProbes.place("button", getPlayer():getSquare())
tripwire = ZedCommTriggerProbes.place("tripwire", getPlayer():getSquare())
~~~

Place them on separate tiles. Link a free wire to the returned endpoint ID and connect a display to the run. Check that each press or crossing produces one short pulse and that the trigger rearms after clearing.
