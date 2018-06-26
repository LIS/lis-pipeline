# How to configure the Jenkins proccess as a service in systemd

## Tested on
  - Ubuntu 16.04
  - Java 1.8.0_151

## Steps

1 .Add the following config in /etc/systemd/system/jenkins.service

```sh
[Unit]
Description=Jenkins Slave Service
After=network.target

[Service]
User=root
WorkingDirectory=/root/
ExecStart=/usr/bin/java -jar agent.jar -jnlpUrl <insert jnlpUrl here> -secret <insert secret here> -workDir <"insert workspace here">
Restart=always
RestartSec=10                       # Restart service after 10 seconds if node service crashes
StandardOutput=syslog               # Output to syslog
StandardError=syslog                # Output to syslog

[Install]
WantedBy=multi-user.target
```

2. Enable it and start the Jenkins service 

```sh
systemctl enable jenkins.service
systemctl start jenkins.service
```
