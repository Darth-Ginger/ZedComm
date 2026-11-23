# Rain Gauge probe

Install this folder as a local mod alongside ZedComm in a disposable singleplayer debug save. Enable ZedComm Rain Gauge Probe.

Place a test gauge with the Lua console:

~~~lua
gauge = ZedCommRainGaugeProbe.place(getPlayer():getSquare())
~~~

Connect an Advanced Display through a free wire and use the returned gauge ID as the sensor endpoint: `ZedComm.Registry.instance:link("WIRE-ID", gauge, "signal")`. Check exact liters, accumulation outdoors, and fluid transfer to a bottle.
