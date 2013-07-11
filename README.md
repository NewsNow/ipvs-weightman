ipvs-weightman
==============

IPVS Real Server Checker and Weight Manager

Having employed IPVS as our website load balancer since 2000 and
having worked with a number of different real server
monitoring/checker tools over the years, we had built up a long list
of gotchas and issues affecting our ability to adequately maintain our
real servers, minimise human error, and generally keep our website up.

Eventually out of frustration we decided to roll our own:
ipvs-weightman is designed to address these issues, and has now been
employed in our highly available production environment for several
years.

ipvs-weightman aims to provide:

* simple and compact configuration file syntax even for large numbers of virtual and real servers;
* safe and reliable on-the-fly application of configuration file changes, including of weights for disabled realservers;
* safe enabling/disabling of realservers for maintenance: after instructing a realserver to be re-enabled, ipvswm will not turn its weight positive until after a fresh check confirms an OK status;
* safe and reliable resetting of realserver weights following failure detection;
* support for multiple realserver disabled 'reasons'; only when all reasons are removed, will the realserver be enabled;
* a minimal (de-duplicated) set of checkers for hosts attached to multiple virtual services;
* a 'services-up-on-exit' paradigm: ipvsadm won't bring down your load balancer just because it exits;
* persistent storage of checker state, and realserver weights, between ipvswm restarts - so restarting ipvswm is safe and should never break your services (although it can't check your realservers when it's not running!);
* automatic gradual ramping-up of weights when a realserver is enabled that has been disabled for some time;
* management console, accessible by telnet/socat/fifo, with command-line interface that provides:
  * visibility of decision engine state;
  * on-the-fly manual override of realserver weight for specified virtual servers;
  * on-the-fly disabling/enabling realservers for specified virtual servers;
  * option to enable realservers gradually through specification of a ramping up time;
  * easy scriptability (e.g. loop through active real servers: turn server off, wait for server quiescence, roll out code/config updates, restart processes/apache, turn server on smoothly)
* clear and transparent logging of decision engine actions to any combination of file, syslog or stderr;
* configurable sorry server, activated when all realservers on a virtual service have weight zero, or indeed when there are none!
* optional email alerts, on enabling/disabling of sorry server;
* automatic configuration file reloading; optionally manually-triggered config file reloading by management console command.

Config File Format
------------------

### Global options

    # GLOBAL OPTIONS
    # key=value
    #
    Email.Headers.From=my-ipvs-host@myorg.org
    Email.Headers.To=it-team@myorg.org
    Email.Headers.Reply-To=it-team@myorg.org
    Email.SMTP=192.168.1.1
    Ramping.TriggerTime=120
    Ramping.Duration=10
    
    Config.AutoCheck=1
    Config.CheckPeriod=1

    Log.Path=/var/log/ipvs-weightman/ipvs-weightman.log
    Log.SysLog=1
    Log.StdErr=1 # Only when running with --nofork

    # Must be placed in non-persistent filesystem e.g. tmpfs, so it does not survive a reboot!
    DB=/var/run/ipvs-weightman.db

    # Management console
    Management.Socket.IP=127.0.0.1
    Management.Socket.Port=9000

    # Sorry server: default host entry
    SorryServer.Default=mysorryserver

    SorryServer.Fallback.Host=mysorryserver
    SorryServer.Fallback.Title=mysorryserver
    SorryServer.Fallback.IP=192.168.1.10

### VS configuration

    # VIRTUAL SERVICES
    # Tag Host:Port[:DefaultRealServerPort] HTTP-Check-Path Options
    
    ! www 1.2.3.4:80 http://mysite.org/mycheck1 email=true,sorry_server=mysorryserver
    ! srv 1.2.3.5:8080:80 http://mysite.org/mycheck2

### Host configuration

    # HOSTS AND WEIGHTS
    # Tag Host[:Port] <service tag1>=<weight1> <service tag2=weight2> ...
    #
    # Host can be hostname or IP
    
    mysorryserver 192.168.1.10
    srv1 srv1.int www=100 srv=10
    srv2 srv2.int www=200 srv=20
    srv3 192.168.1.20 www=300

