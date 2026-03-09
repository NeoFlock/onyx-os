Kocos.E2BIG = "too many arguments"
Kocos.EACCESS = "permission denied"
Kocos.EAGAIN = "resource temporarily unavailable"
Kocos.EBADF = "bad file descriptor"
Kocos.EBADMSG = "bad message"
Kocos.ECHILD = "no child processes"
Kocos.EEXIST = "file exists"
Kocos.EFBIG = "file too large"
Kocos.EHWPOISON = "critical driver error"
Kocos.EINVAL = "invalid argument"
Kocos.EIO = "I/O error"
Kocos.EISDIR = "is a directory"
Kocos.ELIBACC = "cannot access shared library"
Kocos.ELIBBAD = "invalid shared library"
Kocos.ELIBEXEC = "cannot exec a shared library"
Kocos.ELOOP = "too many symbolic links"
Kocos.ENAMETOOLONG = "name too long"
Kocos.ENODEV = "no such device"
Kocos.ENOENT = "no such file or directory"
Kocos.ENOEXEC = "exec format error"
Kocos.ENOSYS = "invalid syscall"
Kocos.ENOTBLK = "block device required"
Kocos.ENOTDIR = "not a directory"
Kocos.ENOTEMPTY = "directory not empty"
Kocos.ENOTSOCK = "not a socket"
Kocos.EPERM = "operation not permitted"
Kocos.EPIPE = "broken pipe"
Kocos.EPROTO = "protocol error"
Kocos.EPROTONOSUPPORT = "protocol not supported"
Kocos.EPROTOTYPE = "protocol wrong type for socket"
Kocos.ERESTART = "syscall requires restart"
Kocos.ESPIPE = "invalid seek"
Kocos.ESRCH = "no such process"
Kocos.ESTRPIPE = "streams pipe error"
Kocos.ETIME = "timer expired"
Kocos.EUNATCH = "driver not attached"
Kocos.ENODRIVER = Kocos.EUNATCH
Kocos.ETIMEDOUT = "connection timed out"
Kocos.EROFS = "read-only filesystem"
Kocos.ENETDOWN = "network is down"
Kocos.EISCONN = "socket is connected"
Kocos.ECANCELED = "operation cancelled"
Kocos.EALREADY = "connection already in progress"
Kocos.EADDRINUSE = "address already in use"
Kocos.EADDRNOTAVAIL = "address not available"
Kocos.EAFNOSUPPORT = "address family not supported"
Kocos.EXDEV = "invalid cross-device link"
Kocos.EHOSTISDOWN = "host is unreachable"
Kocos.ENOIMPL = "not implemented"
Kocos.ENOSUPPORT = "not supported"

---@return table<string, string>
function syscalls.errnos()
	local errnos = {}
	for k, v in pairs(Kocos) do
		if type(k) == "string" and k == string.upper(k) and string.sub(k, 1, 1) == "E" and type(v) == "string" then
			errnos[k] = v
		end
	end
	return errnos
end
