--!lua

k.registerDaemon("syslogd", function(cpid, severity, msg)
	Kocos.printkf(severity, msg)
	return true
end)

k.invokeDaemon("initd", "markComplete")
