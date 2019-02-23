
# Generic WPAD/PAC file creation

## About

As a result of managing a network with ~100 sites, I quickly got fed up with editing wpad files (also known as PAC files) by hand, and it was frankly unmanagable.

Over time I created a script to batch generate the files for each site and copy them to the relevant IIS server.

This also became tedious.

This is probably the final evolution of my initial local script.

We deploy this script bundle via DFS. Everything needed for it to run on every site (including sites that don't yet exist!) is included in the DFS folder, and very little setup is required on the server (or servers!) hosting IIS.

### Migration

We moved from having internal proxy servers, to using a cloud based solution so it was important that it was simple to be able to direct each site to the appropriate cloud based proxies for their location, which is another advantage of this method - if you want to change the proxy for a site it is a simple DNS change with no scripting knowledge requried, which also means less chance of a typo!

# Overview

This is mostly driven by DNS.

Assuming that the DNS domain you are setting on your clients is example.com, the proxy autodetect on (most) browsers will check for <http://wpad.example.com/wpad.dat> by default. So included is a simple IIS level redirect rule to handle that.

You can also indicate to clients via DHCP option 252 that you wish them to use a specific WPAD URL.

# Setup

## DNS Settings

There are two components here, one for the proxies, and one for the wpad servers. Each will have a wildcard DNS A Record to be the catchall, and then individual A or CNAME records related to the individual sites.

### Wildcard DNS entries

Fallback or default records
|Record|Type|Value|Note
|---|--|--|--
|*.wpad.example.com|A|10.1.2.3|IP Address of the fallback server. Can have multiple Records for DNS round robin load balancing.
|*.proxy.example.com|A|10.1.2.4|IP Address of the fallback proxy server.

Note, these MUST be A records, the wildcard does not support CNAMEs.

### WPAD Site level DNS records

|Record|Type|Value|Note
|---|--|--|--
|site1.wpad.example.com | CNAME | server1.example.com. | Webserver hosting wpad for AD site "site1"
|site2.wpad.example.com | A | 10.2.2.2 | IP of serve hosting wpad for AD site "site2"

### Proxy Site level DNS records

Extremely similar to the way you will have setup the WPAD DNS records

|Record|Type|Value|Note
|---|--|--|--
|site1.proxy.example.com | CNAME | proxy1.example.com. | Webserver hosting wpad for AD site "site1"
|site2.proxy.example.com | A | 10.3.2.2 | IP of serve hosting wpad for AD site "site2"

**WARNING** remember if you use a CNAME to include a trailing full stop/period character at the end of the server FQDN!

# In use

A client from  the subnet subnet associated with AD site "site1" with no DHCP option 252 configured will <http://wpad.example.com/wpad.dat> as it's autoconfigure address.

This can either redirect the client requesting a file to a specific wpad file (maybe local to the client) or just serve up the full WPAD file via the scripts.

It is immaterial what the hostname or server of the site that is hit is, the scripts generate a file based on the AD site that the requesting client is in.

We use a redirect rule on the Default Website of our main IIS server to redirect any client requesting /wpad.dat to a specific hostname. An example rule to include in *web.config* is included in the DefaultRedirect folder.

Note that servers on static IPs will not query DHCP for option 252, so will always fallback to the default URL.

## Per site

### wpad

You can steer clients at a site to <http://sitename.wpad.example.com/wpad.dat> using DHCP option 252 so they are accessing a local webserver, or they can all go back to a central server. The wpad file they are served will be the same.

### Proxy server

The advantage to these scripts is more about steering clients to the correct proxy for their site.

It is assumed that all proxies only use port 8080, and there is no split between ports for http or https traffic.

## wpad.dat Script

Once a client hits the /wpad.dat script included, the magic happens.

1. The wpad.dat ASP file runs, and determines the requesting client IP address and IP Block (based on /24 subnets)
2. If the cached file for that IP Block is still fresh enough, the cached version is served to the client.
3. Otherwise, the wpad.ps1 file is executed, which determines the clients AD site from its IP address using the nltest command.
4. The PowerShell script then amalgamates all the JavaScript snippets from the wpad.d and \<sitename\>.d (if it exists!) folders, ordered on their filenames and returns this to the ASP script
5. The ASP script caches the output and then returns it to the client.

## Javascript Snippets

*In future I'll provide a custom.d folder hook to allow overriding some of the standard files in the wpad.d folder.*

There is always that one application that hates proxies (I'm looking at you Java, and almost every bank..) or some site that restricts access from an IP range (hello various Governments) which means traffic to that site must either go direct (and you have a related firewall rule created to the target IP) or go via a specific site.

For every site you need something different on, create a folder called \<site\>.d and then create files XX.Name.txt e.g. "40.LOCAL EXCLUSIONS.txt" and create your own bypass rules.

You can be as flexible as you need to be. For inspiration, check the examples.d folder, and for help with syntax and troubleshooting you can check out <https://findproxyforurl.com/> - note there are a very limited amount of [functions](https://findproxyforurl.com/pac-functions/) you can use!

## Debugging

If you add ?debug to the URL, the server will return the file with a MIME type of text/plain instead of application/x-ns-proxy-autoconfig - this means your browser will display the file instead of trying to download it.

This also bypasses the cache.

## Server configuration

### DFS

We have the scripts in a folder which is part of a DFS Replication Group. This is added to each IIS server as a website so updating every server hosting a wpad file is completely painless and happens very quickly.

Everything needed from the filesystem point of view is already included in the web.config file so you should just need to add a website for sitename.wpad.example.com once you have configured IIS...

### IIS

The script bootstraping PowerShell is classic ASP, so you need to add this feature to your IIS Server. For such a small script, rewriting it in ASP.Net feels like overkill.

Using the included redirect rule requires installing the IIS rewrite module.

### DNS

If you want to return a file or redirect from the server hosting wpad.example.com you will need to remove the wpad name from the default GlobalQueryBlocklist on Windows DNS servers.

To rectify this, you must update every DNS server, you can find instructions on manipulating this paramater on [Microsofts docs](https://docs.microsoft.com/en-us/powershell/module/dnsserver/set-dnsserverglobalqueryblocklist?)

### Clients

If a client cannot resolve an autoconfigure script, it will attempt to go direct.

You can either configure your clients browsers to:

1. use autodetect and resolve using the above methods
2. use a specific wpad file via DHCP option 252
   - only works for client with a DHCP IP, not a static IP
   - may not work with Firefox
3. use a specific wpad file via GPO e.g. specifying the URL explicity for IE

Using this structure also means that when you have a non-Windows device that needs Internet access for updates or such, that you can simply configure the device to use sitename.proxy.example.com:8080 and it will find it's way to the internet - either via a local proxy or the default proxy.

If you change the proxy for a site in future, it's a simple DNS update and all clients directed to that hostname will update with no additional configuration required!

# Enhancements

Please submit a pull request if you can get IIS to directly execute PowerShell
with access to the Application and Request objects!